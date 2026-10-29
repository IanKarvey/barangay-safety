-- ============================================================================
-- Migration: final feature batch (§4.2–4.5, §8 extended, §12)
-- Date: 2026-08-18
-- ============================================================================
--
-- PURPOSE
--   One file, five features, so it is pasted once:
--
--     PART 1  §8   Three-photo ID verification (front, back, selfie-with-ID)
--     PART 2  §8   Guardian details for under-18 registrations (RA 10173)
--     PART 3  §4.2 Duplicate report linking
--     PART 4  §4.3 Perceptual image hash
--     PART 5  §4.5 Trust scoring
--     PART 6  §12  Duplicate account detection
--
-- SAFETY
--   Additive only. Every statement is `IF NOT EXISTS` or `CREATE OR REPLACE`.
--   No column is dropped, renamed, or retyped; no existing policy is replaced.
--   Nothing here can strand data that already exists.
--
--   In particular `profiles.id_photo_url` is KEPT AS-IS and reinterpreted as
--   the FRONT of the ID. Every submission made since 2026-08-16 stays valid
--   and needs no re-upload. Renaming it to `id_front_url` would have been
--   tidier and would have silently invalidated every ID already on file.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- PART 1 — §8 Three-photo ID verification
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THREE PHOTOS AND NOT FACE RECOGNITION
--   The goal is "the person holding this ID is the person on it". Face
--   recognition answers that with a biometric template, which under RA 10173
--   is sensitive personal information carrying its own consent, retention and
--   breach-notification duties — for a barangay with no data protection
--   officer, that is a liability, not a feature.
--
--   A selfie holding the ID answers the same question with a human glance and
--   stores no biometric template at all. It is what GCash and the banks
--   actually do. The back of the ID is what makes the front checkable: the
--   security features, signature panel and control numbers live there.
--
--   So: three ordinary photographs, reviewed by a person. No biometrics.

ALTER TABLE public.profiles
  -- `id_photo_url` (existing) is the FRONT. Not renamed — see SAFETY above.
  ADD COLUMN IF NOT EXISTS id_back_url    TEXT,
  ADD COLUMN IF NOT EXISTS id_selfie_url  TEXT,
  -- Which document was presented. Drives the §8 student extension in PART 2:
  -- a school ID is accepted, but it identifies a minor, so it pulls in the
  -- guardian requirement.
  ADD COLUMN IF NOT EXISTS id_type        TEXT;

COMMENT ON COLUMN public.profiles.id_photo_url IS
  'FRONT of the submitted ID. Sensitive personal information (RA 10173). Private bucket; readable only by the owner, their barangay officials, and the superadmin.';
COMMENT ON COLUMN public.profiles.id_back_url IS
  'BACK of the submitted ID — security features and control numbers. Same protection as the front.';
COMMENT ON COLUMN public.profiles.id_selfie_url IS
  'Selfie holding the ID, for human comparison against the front. NOT a biometric template: no face embedding is computed or stored anywhere in this system.';

-- Reviewers work oldest-first. Partial index because the overwhelming
-- majority of profiles have submitted nothing and never will.
CREATE INDEX IF NOT EXISTS idx_profiles_id_pending
  ON public.profiles(id_submitted_at)
  WHERE id_submitted_at IS NOT NULL AND is_verified = FALSE;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 2 — §8 Guardian details for under-18 registrations
-- ════════════════════════════════════════════════════════════════════════════
--
-- RA 10173 requires consent from a parent or guardian to process a minor's
-- personal information. The app already collects `date_of_birth` (since
-- 2026-08-11), so it already knows who is a minor — it just did nothing with
-- that knowledge. These columns close that gap.
--
-- `guardian_consent_at` is a TIMESTAMPTZ, not a boolean, for the same reason
-- `privacy_consent_at` is: a boolean cannot answer "which version of the
-- notice did they agree to", and silently keeps saying yes after a revision.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS guardian_name         TEXT,
  ADD COLUMN IF NOT EXISTS guardian_phone        TEXT,
  ADD COLUMN IF NOT EXISTS guardian_relationship TEXT,
  ADD COLUMN IF NOT EXISTS guardian_consent_at   TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.guardian_consent_at IS
  'When a parent/guardian consented to processing this minor''s data (RA 10173). Timestamp not boolean, so a revised privacy notice invalidates stale consent.';

-- DELIBERATELY NOT A CHECK CONSTRAINT.
--   A constraint like "under 18 implies guardian_name IS NOT NULL" would
--   reject every historical profile the moment someone touched an unrelated
--   column, and would block an official from fixing a typo on a minor's
--   record. The requirement is enforced in the registration form, where it
--   can explain itself. Left as a reporting query instead:
--
--     SELECT id, full_name, date_of_birth FROM public.profiles
--     WHERE date_of_birth > (CURRENT_DATE - INTERVAL '18 years')
--       AND guardian_consent_at IS NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 3 — §4.2 Duplicate report linking
-- ════════════════════════════════════════════════════════════════════════════
--
-- "Same fire, five uploaders" currently becomes five unrelated incidents, five
-- dispatches, and five separate resolutions.
--
-- CRITICAL DESIGN POINT: this NEVER auto-merges.
--   Two genuine emergencies can happen next door to each other within minutes
--   — a fire that spreads, a brawl that splits. Auto-merging those loses one
--   of them, and losing an emergency is a far worse failure than showing an
--   official one extra card. So the detector only ever *suggests*; an official
--   confirms, and only then is `duplicate_of_id` set.
--
-- ON DELETE SET NULL, not CASCADE: deleting a parent must never delete the
-- reports linked to it.

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS duplicate_of_id UUID
    REFERENCES public.incidents(id) ON DELETE SET NULL,
  -- Set when an official has looked at a suggestion and said "not a
  -- duplicate". Without this the same pair is re-suggested forever and the
  -- feature becomes noise the officials learn to ignore.
  ADD COLUMN IF NOT EXISTS duplicate_checked_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_incidents_duplicate_of
  ON public.incidents(duplicate_of_id)
  WHERE duplicate_of_id IS NOT NULL;

-- The detector's lookup: recent incidents in one barangay. Ordering by
-- created_at DESC matches how the query actually reads.
CREATE INDEX IF NOT EXISTS idx_incidents_barangay_created
  ON public.incidents(barangay_id, created_at DESC);


-- ════════════════════════════════════════════════════════════════════════════
-- PART 4 — §4.3 Perceptual image hash
-- ════════════════════════════════════════════════════════════════════════════
--
-- A 64-bit dHash of the first photo, stored as 16 hex characters. Catches the
-- case proximity matching cannot: the same photograph forwarded around a
-- group chat and re-uploaded by five people, sometimes hours later and with
-- different GPS because they were not there.
--
-- Perceptual, not cryptographic — resizing, recompression and small crops
-- produce a near-identical hash, which is the entire point. Two images are
-- compared by Hamming distance, so this is a TEXT column and not a hash index.
--
-- Computed on the device before upload: no server cost, and it works on the
-- original image rather than whatever compression the bucket applied.

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS photo_hash TEXT;

COMMENT ON COLUMN public.incidents.photo_hash IS
  '64-bit dHash of the first photo as 16 hex chars. Perceptual — compare with Hamming distance, never with equality.';


-- ════════════════════════════════════════════════════════════════════════════
-- PART 5 — §4.5 Trust scoring
-- ════════════════════════════════════════════════════════════════════════════
--
-- Answers "how much weight should an official give this report?" from the
-- reporter's own history. Reads as SECURITY DEFINER so an official gets the
-- score without needing SELECT on every incident row belonging to that user.
--
-- WHAT THIS IS NOT
--   It is not a gate. Nothing in the app refuses a report because of a score,
--   and nothing should: the person with the worst history can still be the one
--   watching a house burn down. It orders a queue and it annotates a card.
--
-- SCORE SHAPE — 0..100, starting at 70
--   +15  verified account (they stood behind an ID)
--   +10  five or more reports that were resolved, not flagged
--   -25  per false-report strike
--   -20  currently locked
--   Clamped to 0..100. The weights are deliberately blunt: a precise-looking
--   score invites officials to treat it as fact rather than as a hint.

CREATE OR REPLACE FUNCTION public.get_trust_score(p_user_id UUID)
RETURNS TABLE (
  score            INT,
  total_reports    INT,
  resolved_reports INT,
  flagged_reports  INT,
  strikes          INT,
  is_verified      BOOLEAN,
  is_locked        BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total    INT;
  v_resolved INT;
  v_flagged  INT;
  v_strikes  INT;
  v_verified BOOLEAN;
  v_locked   BOOLEAN;
  v_score    INT;
BEGIN
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE i.status IN ('resolved', 'closed')),
    COUNT(*) FILTER (WHERE i.status = 'flagged')
  INTO v_total, v_resolved, v_flagged
  FROM public.incidents i
  WHERE i.reporter_id = p_user_id;

  SELECT
    COALESCE(p.false_report_strikes, 0),
    COALESCE(p.is_verified, FALSE),
    COALESCE(p.is_locked, FALSE)
  INTO v_strikes, v_verified, v_locked
  FROM public.profiles p
  WHERE p.id = p_user_id;

  -- No profile row (a deleted account, or a non-resident session that never
  -- had one). Return a neutral score rather than NULL — a card rendering
  -- "score: null" is worse than a card rendering the default.
  IF NOT FOUND THEN
    RETURN QUERY SELECT 70, 0, 0, 0, 0, FALSE, FALSE;
    RETURN;
  END IF;

  v_score := 70;
  IF v_verified THEN v_score := v_score + 15; END IF;
  IF v_resolved >= 5 AND v_flagged = 0 THEN v_score := v_score + 10; END IF;
  v_score := v_score - (v_strikes * 25);
  IF v_locked THEN v_score := v_score - 20; END IF;
  v_score := GREATEST(0, LEAST(100, v_score));

  RETURN QUERY SELECT
    v_score, v_total, v_resolved, v_flagged, v_strikes, v_verified, v_locked;
END;
$$;

REVOKE ALL ON FUNCTION public.get_trust_score(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_trust_score(UUID) TO authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 6 — §12 Duplicate account detection
-- ════════════════════════════════════════════════════════════════════════════
--
-- One person, several accounts, is how the §5 false-report strike system gets
-- defeated: collect three strikes, register again, carry on. Phone number is
-- the practical identifier here — it is the callback channel an official
-- actually dials, and a second SIM is a real cost where a second email is free.
--
-- SECURITY DEFINER because the caller is mid-signup and has no permission to
-- read `profiles`.
--
-- ⚠️ KNOWN TRADE-OFF, stated plainly rather than hidden:
--   This is an enumeration oracle. Someone can test numbers one at a time and
--   learn which are registered. Any signup form that says "that number is
--   already taken" has this property; the alternative is silently permitting
--   duplicate accounts, which defeats the strike system this is protecting.
--   Mitigated by returning a bare boolean — no name, no barangay, no status.
--
-- NOT a UNIQUE constraint on purpose: duplicates may already exist, and a
-- unique index would fail to build or start rejecting edits to legitimate
-- shared household numbers. This warns; it does not enforce.

CREATE OR REPLACE FUNCTION public.phone_already_registered(p_phone TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    -- Compares digits only, so 0917-123-4567, +63 917 123 4567 and
    -- 09171234567 are recognised as the same number. Without this the check
    -- is trivially bypassed by adding a dash.
    WHERE regexp_replace(COALESCE(phone, ''), '\D', '', 'g')
          = regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g')
      AND regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g') <> ''
  );
$$;

REVOKE ALL ON FUNCTION public.phone_already_registered(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.phone_already_registered(TEXT) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 7 — §8 Carry guardian details from signup metadata into the profile
-- ════════════════════════════════════════════════════════════════════════════
--
-- Guardian details are collected on the registration form, which runs before
-- the profile row exists and sometimes before a session does. Writing them
-- from the client after signUp() would lose them whenever email confirmation
-- is required — the exact accounts most likely to be a minor's.
--
-- So they ride in `raw_user_meta_data` and a BEFORE INSERT trigger copies them
-- across, mirroring `copy_dob_from_metadata()` from 2026-08-11.
--
-- Separate trigger rather than editing that one: the DOB trigger is applied
-- and working, and there is no reason to risk it to add unrelated columns.

CREATE OR REPLACE FUNCTION public.copy_guardian_from_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  meta JSONB;
BEGIN
  SELECT u.raw_user_meta_data INTO meta
  FROM auth.users u WHERE u.id = NEW.id;

  IF meta IS NULL THEN
    RETURN NEW;
  END IF;

  -- Only ever fill a gap; never clobber a value already supplied.
  IF NEW.guardian_name IS NULL THEN
    NEW.guardian_name := NULLIF(meta ->> 'guardian_name', '');
  END IF;
  IF NEW.guardian_phone IS NULL THEN
    NEW.guardian_phone := NULLIF(meta ->> 'guardian_phone', '');
  END IF;
  IF NEW.guardian_relationship IS NULL THEN
    NEW.guardian_relationship := NULLIF(meta ->> 'guardian_relationship', '');
  END IF;
  IF NEW.guardian_consent_at IS NULL THEN
    NEW.guardian_consent_at :=
      NULLIF(meta ->> 'guardian_consent_at', '')::TIMESTAMPTZ;
  END IF;

  RETURN NEW;
EXCEPTION
  -- Malformed metadata must never block account creation. Losing the guardian
  -- record is recoverable by an official editing the profile; a registration
  -- that fails at 2am during an emergency is not.
  WHEN others THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_copy_guardian ON public.profiles;

CREATE TRIGGER profiles_copy_guardian
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.copy_guardian_from_metadata();

COMMIT;


-- ════════════════════════════════════════════════════════════════════════════
-- STEP 2 — verify (run this after the COMMIT above succeeds)
-- ════════════════════════════════════════════════════════════════════════════

-- Expect 7 rows: id_back_url, id_selfie_url, id_type, guardian_name,
-- guardian_phone, guardian_relationship, guardian_consent_at
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
  AND column_name IN ('id_back_url','id_selfie_url','id_type',
                      'guardian_name','guardian_phone','guardian_relationship',
                      'guardian_consent_at')
ORDER BY column_name;

-- Expect 3 rows: duplicate_of_id, duplicate_checked_at, photo_hash
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'incidents'
  AND column_name IN ('duplicate_of_id','duplicate_checked_at','photo_hash')
ORDER BY column_name;

-- Expect both functions present.
SELECT proname, prosecdef AS security_definer
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('get_trust_score','phone_already_registered')
ORDER BY proname;

-- Expect a score of 70 and all-zero counts for a random UUID.
SELECT * FROM public.get_trust_score('00000000-0000-0000-0000-000000000000'::uuid);

-- Expect FALSE.
SELECT public.phone_already_registered('09000000000');

-- Expect one row: profiles_copy_guardian / INSERT / BEFORE.
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'profiles'
  AND trigger_name = 'profiles_copy_guardian';
