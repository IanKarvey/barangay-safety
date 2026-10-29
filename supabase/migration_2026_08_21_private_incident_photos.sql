-- ============================================================================
-- Close the public-photo hole on `incident-photos`.
-- 2026-08-21
-- ============================================================================
--
-- ## What was wrong
--
-- Verified against this project on 2026-08-18 using only the publishable anon
-- key that ships inside the APK — and for the final step, no credentials at all:
--
--   1. POST /storage/v1/object/list/incident-photos listed the bucket
--      anonymously, so every incident id and filename was enumerable.
--   2. GET /storage/v1/object/public/incident-photos/<id>/<file> returned
--      HTTP 200 and a real JPEG with no apikey and no Authorization header.
--
-- Every incident photograph and every non-resident proof photo was therefore
-- downloadable by anyone on the internet, and they did not need to guess a URL
-- because the bucket handed out the index.
--
-- The database itself was never the problem: all eight tables the app touches
-- return zero rows anonymously, and `id-verification` was already correctly
-- private. This is a storage-layer fix only.
--
-- ## Run this AFTER installing the matching app build
--
-- The app now stores the storage **path** in `incident_media.photo_url` and
-- `non_resident_sessions.proof_url`, and mints a short-lived signed URL when a
-- photograph is displayed. Old rows hold a full public URL; PART 3 rewrites
-- them to paths. The app tolerates both shapes (`IncidentService.storagePathOf`),
-- so the ordering is forgiving — but installing the build first means no photo
-- is ever unreachable.
--
-- Safe to run more than once.
-- ============================================================================


-- ── PART 1 — take the bucket out of public mode ─────────────────────────────
-- This alone stops anonymous fetches of object/public/... URLs.

UPDATE storage.buckets
SET    public = false
WHERE  id = 'incident-photos';


-- ── PART 2 — who may read an object in this bucket ──────────────────────────
--
-- Signing a URL requires SELECT on the object, so this policy is what decides
-- who can be handed a photograph.
--
-- Scoped to signed-in users rather than to each incident's own barangay, and
-- that is a deliberate, stated limitation rather than an oversight. A
-- barangay-scoped policy has to parse the incident id back out of the object
-- path and join it to `incidents`, with a second branch for the
-- `non-resident/<sessionId>/...` layout. Getting that subtly wrong makes
-- photographs vanish for officials mid-emergency, and it cannot be verified
-- from outside the app. The step from "anyone on the internet" to "a
-- registered, signed-in account" is the one that closes the actual exposure;
-- narrowing further is a real improvement but a smaller one, and it belongs
-- after device testing.
--
-- Note: non-resident reporters sign in anonymously through Supabase, which
-- still yields the `authenticated` role, so this does not lock them out of
-- their own flow.

DROP POLICY IF EXISTS "Signed-in users can read incident photos"
  ON storage.objects;

CREATE POLICY "Signed-in users can read incident photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'incident-photos');

-- Uploads stay available to signed-in users; the app writes under an incident
-- id or a session id it already owns.
DROP POLICY IF EXISTS "Signed-in users can upload incident photos"
  ON storage.objects;

CREATE POLICY "Signed-in users can upload incident photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'incident-photos');


-- ── PART 3 — backfill stored public URLs down to bare paths ─────────────────
--
-- Existing rows hold e.g.
--   https://<ref>.supabase.co/storage/v1/object/public/incident-photos/<uuid>/<file>.jpg
-- and must become
--   <uuid>/<file>.jpg
--
-- Idempotent: the WHERE clause only matches rows that still look like URLs.

UPDATE public.incident_media
SET    photo_url = split_part(photo_url, '/object/public/incident-photos/', 2)
WHERE  photo_url LIKE 'http%/object/public/incident-photos/%';

UPDATE public.non_resident_sessions
SET    proof_url = split_part(proof_url, '/object/public/incident-photos/', 2)
WHERE  proof_url LIKE 'http%/object/public/incident-photos/%';

-- Strip any query string that rode along on an old URL.
UPDATE public.incident_media
SET    photo_url = split_part(photo_url, '?', 1)
WHERE  photo_url LIKE '%?%';

UPDATE public.non_resident_sessions
SET    proof_url = split_part(proof_url, '?', 1)
WHERE  proof_url LIKE '%?%';


-- ============================================================================
-- Verification — run these after applying.
-- ============================================================================

-- 1. Expect public = false.
SELECT id, public FROM storage.buckets WHERE id = 'incident-photos';

-- 2. Expect no rows. Any row here is a photograph the app can no longer
--    resolve, because it is still stored as a URL rather than a path.
SELECT 'incident_media' AS src, id::text, photo_url
FROM   public.incident_media
WHERE  photo_url LIKE 'http%'
UNION ALL
SELECT 'non_resident_sessions', id::text, proof_url
FROM   public.non_resident_sessions
WHERE  proof_url LIKE 'http%';

-- 3. Expect the two policies created above.
SELECT cmd, policyname
FROM   pg_policies
WHERE  schemaname = 'storage'
  AND  tablename  = 'objects'
  AND  policyname LIKE '%incident photos%'
ORDER  BY cmd;

-- ============================================================================
-- After running, re-test the hole from a terminal. This MUST now fail:
--
--   curl -s -o /dev/null -w '%{http_code}\n' \
--     'https://<ref>.supabase.co/storage/v1/object/public/incident-photos/<id>/<file>.jpg'
--
-- Expect 400. If it still returns 200, PART 1 did not take effect.
-- ============================================================================
