-- ============================================================================
-- Migration: Superadmins are visible to reporters city-wide
-- Date: 2026-08-09
-- Requirement: §1 — reporter must see help approaching
-- ============================================================================
--
-- PROBLEM (found on device 2026-08-09)
--   A superadmin turned on location sharing and never appeared for the
--   reporter. Diagnosis showed the responder sat in barangay 192fc02d… while
--   the reporter's GPS resolved to 40ca59b4… — so the barangay filter
--   excluded them, correctly by the letter of the code and wrongly in effect.
--
--   A superadmin oversees the whole city. Scoping them to a single barangay
--   is simply wrong: they should be reachable to any reporter.
--
-- FIX
--   Expose `role` on the view so the client can keep barangay scoping for
--   ordinary officials while treating superadmins as city-wide.
--
--   `role` is not personal data — it is a job classification, and the view
--   still withholds email, phone, address and ID photo. This does not widen
--   what a reporter learns about a person.
--
-- Safe to re-run (idempotent).
-- ============================================================================

-- NOTE: `role` is APPENDED LAST, not inserted mid-list. CREATE OR REPLACE
-- VIEW can only add columns at the end — inserting one in the middle reads as
-- renaming an existing column and fails with 42P16. Column order is
-- irrelevant here since the client reads by name.
CREATE OR REPLACE VIEW public.responder_locations AS
  SELECT
    p.id,
    p.full_name,
    p.position,
    p.barangay_id,
    p.last_lat,
    p.last_lng,
    p.last_location_at,
    p.role                  -- NEW: lets the client scope barangay vs city-wide
  FROM public.profiles p
  WHERE p.is_sharing_location = TRUE
    AND p.last_lat IS NOT NULL
    AND p.last_lng IS NOT NULL
    AND p.is_locked = FALSE;

GRANT SELECT ON public.responder_locations TO authenticated;


-- ============================================================================
-- VERIFY
-- ============================================================================
--   SELECT full_name, role, position, barangay_id FROM public.responder_locations;
--
-- Confirm the view still withholds identifying data — the result should be
-- exactly: id, full_name, position, role, barangay_id, last_lat, last_lng,
-- last_location_at. No email, phone, address or id_photo_url.
