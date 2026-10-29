-- ============================================================================
-- Migration: remote ID verification (§8)
-- Date: 2026-08-16
-- ============================================================================
--
-- PURPOSE
--   Replace the in-person barangay hall trip with an ID photo uploaded from
--   the app. `profiles.id_photo_url` and the `id-verification` bucket already
--   existed; nothing ever wrote to them and no storage policies were defined.
--
-- WHY THIS IS THE CAREFUL ONE
--   A government ID photo is **sensitive personal information** under RA 10173
--   — the strictest category, carrying both an ID number and a face. Incident
--   photos are ordinary personal information; these are not, and a leak here is
--   materially worse than a leaked incident photo.
--
--   So the bucket is private and reads are restricted to exactly three parties:
--     1. the person who uploaded it,
--     2. officials of THAT PERSON'S barangay,
--     3. the city superadmin.
--
--   An official of a different barangay cannot read it. Other residents cannot
--   read it. There is no public URL.
--
-- PATH CONVENTION — load-bearing, not cosmetic
--   Files are stored as `<user_id>/<filename>`. Every policy below derives
--   ownership from that first path segment, so a user cannot write into
--   someone else's folder and cannot read one.
--
-- SAFETY
--   Wrapped in a transaction. Creates the bucket only if missing and never
--   flips an existing bucket's visibility — if `id-verification` already exists
--   as public, this migration leaves it alone and STEP 2 below reports it, so
--   the change is a deliberate decision rather than a silent side effect.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

-- ── The bucket ─────────────────────────────────────────────────────────────
-- `public = false`: no unauthenticated URL works, ever. Reads go through the
-- policies below or through a short-lived signed URL.
INSERT INTO storage.buckets (id, name, public)
VALUES ('id-verification', 'id-verification', false)
ON CONFLICT (id) DO NOTHING;

-- ── Upload: only into your own folder ──────────────────────────────────────
DROP POLICY IF EXISTS "Users upload their own ID" ON storage.objects;

CREATE POLICY "Users upload their own ID"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'id-verification'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Replace: re-uploading a clearer photo of your own ID ───────────────────
DROP POLICY IF EXISTS "Users replace their own ID" ON storage.objects;

CREATE POLICY "Users replace their own ID"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'id-verification'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Read: the owner, their own barangay's officials, or the superadmin ─────
DROP POLICY IF EXISTS "Owner and reviewing officials read IDs" ON storage.objects;

CREATE POLICY "Owner and reviewing officials read IDs"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'id-verification'
    AND (
      -- The person it belongs to.
      (storage.foldername(name))[1] = auth.uid()::text

      -- Or an official responsible for that person's barangay. Uses the
      -- existing SECURITY DEFINER helpers so this doesn't recurse into the
      -- profiles policies.
      OR EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND (
            get_user_role() = 'superadmin'
            OR (get_user_role() = 'admin' AND p.barangay_id = get_user_barangay())
          )
      )
    )
  );

-- ── Delete: the owner, or a superadmin honouring an erasure request ────────
-- Ties into the RA 10173 deletion path added 2026-08-16: when a deletion
-- request is actioned, the ID photo has to be removable too.
DROP POLICY IF EXISTS "Owner or superadmin deletes IDs" ON storage.objects;

CREATE POLICY "Owner or superadmin deletes IDs"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'id-verification'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR get_user_role() = 'superadmin'
    )
  );

-- ── When the ID was submitted ──────────────────────────────────────────────
-- Separate from `id_photo_url` so an official can sort the review queue by how
-- long someone has been waiting — a resident who cannot report an emergency
-- because nobody reviewed their ID is the failure this feature must avoid.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS id_submitted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.id_photo_url IS
  'Sensitive personal information (RA 10173). Private bucket; readable only by the owner, their barangay officials, and the superadmin.';

COMMIT;


-- ── STEP 2: verify ─────────────────────────────────────────────────────────
-- Expect: public = false, and four policies on the bucket.
SELECT id, public FROM storage.buckets WHERE id = 'id-verification';

SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE '%ID%'
ORDER BY cmd;
