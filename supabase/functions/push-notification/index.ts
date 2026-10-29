// Pushes escalation messages to a phone even when the app is closed.
//
// Wired up as a Supabase DATABASE WEBHOOK on INSERT into public.notifications
// (Dashboard -> Database -> Webhooks). The database job that escalates an
// unanswered report writes one notification row per person to alert; this turns
// each row into a push to that person's phone.
//
// It only handles the escalation types. Everything else in the notifications
// table is left to the app (it already shows those while open), so this does not
// start sending a push for every comment and status change.
//
//   escalation            an official: a report has gone unanswered (the 5 / 10 /
//                         15-minute tiers, then a reminder every 5 minutes)
//   escalation_resident   the resident: officials are busy / whole barangay
//                         alerted / please call these numbers / still waiting
//   responder_update      the resident: "Good news, <role> <name> is responding"
//   responder_taken       the alerted officials: "<role> <name> is responding"
//
// So at every 5-minute mark BOTH sides get a push: the officials who must act and
// the resident who is waiting.
//
// Targeting: each signed-in phone subscribes to the FCM topic `user_<its user
// id>` (lib/providers/notification_provider.dart). A UUID is not guessable, so
// the topic is effectively private to that person, and no device-token table is
// needed.
//
// Setup (one time, in the dashboard):
//   1. Edge Functions -> push-notification -> deploy this file.
//   2. Edge Functions -> Secrets: WEBHOOK_SECRET = any long random string, plus
//      the FIREBASE_PROJECT_ID / FIREBASE_SERVICE_ACCOUNT already used by
//      notify-new-incident.
//   3. Database -> Webhooks -> create: table notifications, event INSERT, type
//      "Supabase Edge Functions" -> push-notification, and add the HTTP header
//        x-webhook-secret: <the same string>
//
// The secret matters: without it anyone who learns the function's URL could make
// it push any text to any user. The function refuses every call if WEBHOOK_SECRET
// is not set, rather than quietly running open.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const FIREBASE_PROJECT_ID = Deno.env.get('FIREBASE_PROJECT_ID')!;
const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET');

const PUSH_TYPES = new Set([
  'escalation',
  'escalation_resident',
  'responder_update',
  'responder_taken',
]);

// ── JWT / OAuth2 helpers (same as notify-new-incident) ──────────────────────

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: FIREBASE_SERVICE_ACCOUNT.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = base64url(new TextEncoder().encode(JSON.stringify(claim)));
  const signingInput = `${header}.${payload}`;

  const pem = FIREBASE_SERVICE_ACCOUNT.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '');
  const keyBytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(signingInput)),
  );

  const jwt = `${signingInput}.${base64url(signature)}`;
  const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const { access_token } = await tokenResp.json();
  return access_token;
}

async function sendToTopic(
  topic: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  const accessToken = await getAccessToken();
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          topic,
          notification: { title, body },
          data,
          android: {
            priority: 'high',
            notification: { sound: 'default', channel_id: 'barangay_safety_channel' },
          },
        },
      }),
    },
  );
  if (!resp.ok) {
    console.error('FCM error:', await resp.text());
    return false;
  }
  return true;
}

// Compare without leaking how many leading characters matched.
function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

serve(async (req) => {
  try {
    // Fail closed: no secret configured -> nobody gets in.
    if (!WEBHOOK_SECRET) {
      return new Response('WEBHOOK_SECRET is not configured', { status: 503 });
    }
    const sent = req.headers.get('x-webhook-secret') ?? '';
    if (!sameSecret(sent, WEBHOOK_SECRET)) {
      return new Response('Unauthorized', { status: 401 });
    }

    const payload = await req.json();
    const record = payload.record;
    if (payload.type !== 'INSERT' || !record) {
      return new Response('Not a new notification', { status: 200 });
    }
    if (!PUSH_TYPES.has(record.type)) {
      return new Response('Not an escalation message', { status: 200 });
    }
    if (!record.user_id) {
      return new Response('No recipient', { status: 400 });
    }

    const data: Record<string, string> = {
      type: String(record.type),
      notificationId: String(record.id ?? ''),
    };
    // Same key the existing handlers read to open the right report on tap.
    if (record.incident_id) data.incidentId = String(record.incident_id);

    const ok = await sendToTopic(
      `user_${record.user_id}`,
      String(record.title ?? 'Barangay Safety'),
      String(record.body ?? ''),
      data,
    );

    return new Response(JSON.stringify({ ok }), {
      status: ok ? 200 : 502,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
