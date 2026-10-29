-- ============================================================================
-- Migration: Data Privacy Act (RA 10173) consent and deletion records
-- Date: 2026-08-16
-- ============================================================================
--
-- WHY
--   The app collects names, addresses, phone numbers, GPS coordinates, photos
--   and dates of birth. Under RA 10173 that is personal information, and the
--   location and image data is sensitive. The Act requires that consent be
--   *demonstrable* — "the user tapped Register" is not a record of consent, so
--   the moment of consent has to be stored.
--
--   It also gives data subjects a right to erasure. A deletion request must be
--   recorded when it is made, not when someone gets around to it, because the
--   compliance clock starts at the request.
--
-- WHY NOT A BOOLEAN
--   `privacy_consent_at` is a timestamp rather than `has_consented BOOLEAN`.
--   A boolean cannot answer "which version of the notice did they agree to, and
--   when" — and if the notice is ever revised, existing consent may no longer
--   cover the new terms. A timestamp can be compared against the notice's
--   effective date; a boolean silently keeps saying yes.
--
-- WHY DELETION IS A REQUEST, NOT A DELETE
--   Erasure is not absolute. Incident records are the barangay's operational
--   and legal record of an emergency response, and deleting a reporter's
--   account must not erase the fact that a fire was reported and answered.
--   Recording the request lets a human resolve that properly — anonymise the
--   reporter, keep the incident. An immediate cascade delete would destroy
--   evidence the barangay is obliged to keep.
--
-- SAFETY
--   Additive only. Both columns are nullable; existing rows read as
--   "no consent recorded", which is accurate — they registered before the
--   notice existed.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS privacy_consent_at TIMESTAMPTZ;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS data_deletion_requested_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.privacy_consent_at IS
  'When the user accepted the privacy notice. RA 10173 requires consent to be demonstrable; a timestamp also allows re-consent if the notice is revised.';

COMMENT ON COLUMN public.profiles.data_deletion_requested_at IS
  'When the user asked for erasure. A request, not an action: incident records are the barangay operational record and must be resolved by a human, not cascade-deleted.';

-- Officials need to find outstanding deletion requests. Partial, because the
-- overwhelming majority of rows are NULL and never searched.
CREATE INDEX IF NOT EXISTS idx_profiles_deletion_requested
  ON public.profiles (data_deletion_requested_at)
  WHERE data_deletion_requested_at IS NOT NULL;

COMMIT;


-- ── Verify ─────────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND column_name IN ('privacy_consent_at', 'data_deletion_requested_at');
