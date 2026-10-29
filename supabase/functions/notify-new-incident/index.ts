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

  // Import RSA private key from service account PEM
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
    const err = await resp.text();
    console.error('FCM error:', err);
  }
}

// ── Severity helpers ─────────────────────────────────────────────────────────

// Severity runs 4 (worst) down to 1 (least) — flipped on 2026-08-25, see
// lib/utils/severity.dart. This table kept the old direction (1 = CRITICAL) for
// two months, so every push said the opposite of the truth: a fire arrived as
// "LOW Incident Reported" and a noise complaint as "CRITICAL". If the scale is
// ever reversed again, this is one of the two places outside the app that has to
// change with it (the other is the severity guide in suggest-severity).
const SEVERITY_EMOJI: Record<number, string> = {
  4: '🚨',
  3: '⚠️',
  2: '🔔',
  1: 'ℹ️',
};

const SEVERITY_LABEL: Record<number, string> = {
  4: 'CRITICAL',
  3: 'HIGH',
  2: 'MEDIUM',
  1: 'LOW',
};

// ── Main handler ─────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;

    if (!record) return new Response('No record', { status: 400 });

    const { id, category, severity_level, barangay_id, status } = record;

    // Only fire on new pending incidents
    if (status !== 'pending') {
      return new Response('Not a new pending incident', { status: 200 });
    }

    const emoji = SEVERITY_EMOJI[severity_level] ?? '📍';
    const label = SEVERITY_LABEL[severity_level] ?? 'NEW';
    const title = `${emoji} ${label} Incident Reported`;
    // "Immediate attention" belongs to High and Critical only. It used to be on
    // every push, so a noise complaint arrived sounding like an emergency.
    const urgent = Number(severity_level) >= 3;
    const body = urgent
      ? `${category} has been reported in your area. Immediate attention may be required.`
      : `${category} has been reported in your area.`;
    const data = {
      incidentId: String(id),
      barangayId: String(barangay_id),
    };

    // Notify officials in that specific barangay
    await sendToTopic(`barangay_${barangay_id}`, title, body, data);

    // Notify superadmin channel
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
