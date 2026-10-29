// Pushes an FCM alert when a non-resident files an emergency report.
//
// Companion to migration_non_resident_notify.sql. The DB trigger covers
// officials with the app open or backgrounded; this covers the app being
// fully closed, which is the case that actually matters at 2am.
//
// DEPLOY
//   supabase functions deploy notify-non-resident-report
//
// WIRE UP (Supabase Dashboard → Database → Webhooks)
//   Table:  non_resident_sessions
//   Events: UPDATE
//   URL:    https://<project>.supabase.co/functions/v1/notify-non-resident-report
//
// SECRETS (same ones the existing notify-new-incident function uses)
//   FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const FIREBASE_PROJECT_ID = Deno.env.get('FIREBASE_PROJECT_ID')!;
const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);

// ── JWT / OAuth2 helpers ─────────────────────────────────────────────────────

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
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      privateKey,
      new TextEncoder().encode(signingInput),
    ),
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

// ── FCM sender ───────────────────────────────────────────────────────────────

async function sendToTopic(
  topic: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const accessToken = await getAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          topic,
          notification: { title, body },
          data,
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channel_id: 'barangay_safety_channel',
            },
          },
        },
      }),
    },
  );

  if (!resp.ok) {
    console.error('FCM error:', await resp.text());
  }
}

// ── Main handler ─────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;
    const oldRecord = payload.old_record;

    if (!record) return new Response('No record', { status: 400 });

    // Fire only on the transition INTO 'reported'. Location updates hit this
    // webhook about once per second, so without this guard every fix would
    // blast a push notification.
    if (record.status !== 'reported' || oldRecord?.status === 'reported') {
      return new Response('Not a new report', { status: 200 });
    }

    const { barangay_id, full_name, phone, id } = record;

    const title = '🚨 Non-Resident Emergency Report';
    const body =
      `${full_name ?? 'A visitor'} reported an emergency and is sharing ` +
      `live location. Contact: ${phone ?? 'unknown'}`;

    const data = {
      sessionId: String(id),
      barangayId: String(barangay_id),
      type: 'non_resident_report',
    };

    // Officials subscribe to barangay_<id> on login (login_screen.dart).
    await sendToTopic(`barangay_${barangay_id}`, title, body, data);
    await sendToTopic('all_incidents', title, body, data);

    return new Response(JSON.stringify({ ok: true }), {
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
