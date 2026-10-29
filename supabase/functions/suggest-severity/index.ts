// ============================================================================
// suggest-severity — AI severity classification from an incident photo (§4.1)
// ============================================================================
//
// WHY THIS IS A SERVER FUNCTION
//   Same reason as send-sms: the Anthropic API key spends money. Calling the
//   API from Flutter would ship the key inside the APK where anyone who unzips
//   it can drain the balance. Here it lives as a Supabase secret.
//
// WHAT IT DOES — AND DELIBERATELY DOES NOT DO
//   It returns a *suggestion*. The app pre-fills nothing and changes nothing on
//   its own: the resident sees "AI suggests Level 1 — Critical" with the reason,
//   and confirms or ignores it. An AI that silently sets severity would be
//   making a dispatch decision with no human in the loop, on evidence as thin as
//   one photo.
//
// SETUP
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy suggest-severity
//
//   Without the secret it returns 200 with suggested: null — the report form
//   works exactly as it does today.
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const ANTHROPIC_ENDPOINT = 'https://api.anthropic.com/v1/messages';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

// The four levels the app already uses. Kept verbatim so the model's answer
// maps onto the existing enum with no translation layer to drift.
const SEVERITY_GUIDE = `
Level 1 - Critical / Life-Threatening: immediate danger to life. Fire, active
  assault, drowning, severe injury, structural collapse.
Level 2 - High / Serious: serious incident needing urgent attention. Robbery in
  progress, vehicular accident with injury, domestic violence, medical emergency.
Level 3 - Medium / Moderate: needs a timely response but no immediate danger.
  Theft after the fact, vandalism, minor accident, suspicious activity.
Level 4 - Low / Minor Disturbance: community concern. Noise complaints, litter,
  minor public disturbance.
`.trim();

const SYSTEM_PROMPT = `You assist a Philippine barangay emergency reporting app.

Given a photo of an incident and the reporter's description, suggest which
severity level best fits, using this scale:

${SEVERITY_GUIDE}

Judge only what is visible and what the reporter wrote. Do not speculate beyond
the evidence.

If the photo is too dark, blurred, or unrelated to the description to judge,
return level 0 with a one-line reason. A refusal to guess is more useful than a
confident wrong answer, because a barangay may dispatch on this.

Reply as JSON only: {"level": <0-4>, "reason": "<one short sentence>"}
The reason is shown to a resident in plain language - keep it under 15 words.`;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  try {
    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');

    // 200, not 500. The report form treats a null suggestion as "no suggestion
    // available" and carries on; an unconfigured classifier must never look
    // like a broken report form.
    if (!apiKey) {
      return json({ suggested: null, reason: 'ANTHROPIC_API_KEY not configured' });
    }

    const { imageBase64, mediaType, description, category } = await req.json();

    if (typeof imageBase64 !== 'string' || !imageBase64) {
      return json({ error: 'imageBase64 is required' }, 400);
    }

    const res = await fetch(ANTHROPIC_ENDPOINT, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-opus-5',
        // Claude Opus 5 runs adaptive thinking whenever `thinking` is omitted,
        // and max_tokens caps thinking PLUS response text together. The old
        // value of 200 left no room for both, so the JSON reply was truncated.
        max_tokens: 2000,
        // A severity guess from one photo is a classification, not a research
        // task — low effort keeps it cheap and fast without disabling thinking
        // (disabling it on Opus 5 can leak <thinking> tags into the text this
        // function then has to parse JSON out of).
        output_config: { effort: 'low' },
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'image',
                source: {
                  type: 'base64',
                  media_type: mediaType ?? 'image/jpeg',
                  data: imageBase64,
                },
              },
              {
                type: 'text',
                text: `Category the reporter chose: ${category ?? 'not set'}\n` +
                  `Their description: ${description ?? '(none)'}`,
              },
            ],
          },
        ],
      }),
    });

    if (!res.ok) {
      const detail = await res.text();
      console.error('Anthropic error:', res.status, detail.slice(0, 400));

      // Billing and malformed-request failures both arrive as 400s, and
      // telling them apart mattered enough during setup to be worth
      // classifying here rather than digging through function logs.
      let kind = `provider error ${res.status}`;
      try {
        const parsed = JSON.parse(detail);
        const message = String(parsed?.error?.message ?? '');
        if (/credit balance|billing|purchase/i.test(message)) {
          kind = 'billing: credits required';
        } else if (parsed?.error?.type) {
          kind = `${parsed.error.type}: ${message.slice(0, 120)}`;
        }
      } catch (_) {
        // Non-JSON error body — the status code is all there is.
      }
      return json({ suggested: null, reason: kind });
    }

    const data = await res.json();

    // Safety classifiers can decline a request; that arrives as a 200 with
    // stop_reason "refusal" rather than an error status, so it is checked
    // before reading content.
    if (data.stop_reason === 'refusal') {
      return json({ suggested: null, reason: 'declined' });
    }

    const text = (data.content ?? [])
      .filter((b: { type: string }) => b.type === 'text')
      .map((b: { text: string }) => b.text)
      .join('')
      .trim();

    // The model is asked for bare JSON, but a stray code fence or preamble
    // should degrade to "no suggestion" rather than throwing.
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) {
      console.error('Unparseable model reply:', text.slice(0, 200));
      return json({ suggested: null, reason: 'unparseable reply' });
    }

    const parsed = JSON.parse(match[0]);
    const level = Number(parsed.level);

    // Level 0 is the model's "cannot judge" answer, and anything outside 1-4
    // is not a severity this app understands.
    if (!Number.isInteger(level) || level < 1 || level > 4) {
      return json({ suggested: null, reason: String(parsed.reason ?? 'unclear') });
    }

    return json({ suggested: level, reason: String(parsed.reason ?? '') });
  } catch (e) {
    console.error('suggest-severity failed:', e);
    return json({ suggested: null, reason: String(e) });
  }
});
