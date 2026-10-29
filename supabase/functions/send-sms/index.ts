// ============================================================================
// send-sms — Semaphore SMS relay (§11)
// ============================================================================
//
// WHY THIS IS A SERVER FUNCTION AND NOT CLIENT CODE
//   Semaphore authenticates with a single API key that can spend real money.
//   Calling their API from the Flutter app would ship that key inside the APK,
//   where anyone who unzips it can drain the balance. Here the key lives as a
//   Supabase secret and never leaves the server.
//
// WHAT IT IS FOR
//   Emergencies only — full-blast critical alerts (§14). Routine status
//   updates stay on push, which is free. SMS costs about ₱1 per recipient per
//   message, so a barangay with 20 personnel spends ₱20 every time this fires.
//   That cost is exactly why §14 restricts automatic blasts to severity 1.
//
// SETUP
//   1. Create the secret:
//        supabase secrets set SEMAPHORE_API_KEY=your_key_here
//        supabase secrets set SEMAPHORE_SENDER_NAME=BRGYSAFETY   (optional)
//   2. Deploy:
//        supabase functions deploy send-sms
//
//   Until the secret exists the function returns 200 with sent: 0 and a reason,
//   rather than an error — see the note on the caller below.
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const SEMAPHORE_ENDPOINT = 'https://api.semaphore.co/api/v4/messages';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/// Semaphore accepts Philippine mobile numbers as 639XXXXXXXXX.
/// Profiles hold them inconsistently — 09XX, +639XX, with spaces or dashes —
/// so every variant is normalised here rather than trusting the stored format.
function normalisePhLiteral(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');

  if (digits.startsWith('639') && digits.length === 12) return digits;
  if (digits.startsWith('09') && digits.length === 11) return `63${digits.slice(1)}`;
  if (digits.startsWith('9') && digits.length === 10) return `63${digits}`;

  // Anything else is not a PH mobile number. Dropped rather than guessed —
  // sending an emergency alert to a wrong number is worse than not sending it.
  return null;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get('SEMAPHORE_API_KEY');
    const senderName = Deno.env.get('SEMAPHORE_SENDER_NAME') ?? '';

    const { numbers, message } = await req.json();

    if (!Array.isArray(numbers) || typeof message !== 'string' || !message) {
      return new Response(
        JSON.stringify({ error: 'numbers[] and message are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Deliberately a 200, not a 500. The caller fires this alongside a push
    // notification that has already been delivered; an un-configured SMS
    // provider is a missing enhancement, not a failed alert, and must never
    // surface to an official as "the alert failed".
    if (!apiKey) {
      return new Response(
        JSON.stringify({ sent: 0, reason: 'SEMAPHORE_API_KEY not configured' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const valid = [...new Set(
      numbers.map((n: unknown) => normalisePhLiteral(String(n ?? '')))
             .filter((n): n is string => n !== null),
    )];

    if (valid.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, reason: 'no valid PH mobile numbers' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Semaphore takes a comma-separated list and bills per recipient. One call
    // rather than N: a partial failure that alerts some of the hall and not the
    // rest is the worst outcome, because nobody can tell who was missed.
    const body = new URLSearchParams({
      apikey: apiKey,
      number: valid.join(','),
      message,
    });
    if (senderName) body.set('sendername', senderName);

    const res = await fetch(SEMAPHORE_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });

    const text = await res.text();

    if (!res.ok) {
      console.error('Semaphore rejected the send:', res.status, text);
      return new Response(
        JSON.stringify({ sent: 0, reason: `provider error ${res.status}` }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(
      JSON.stringify({ sent: valid.length, provider: text.slice(0, 500) }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    console.error('send-sms failed:', e);
    return new Response(
      JSON.stringify({ sent: 0, reason: String(e) }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
