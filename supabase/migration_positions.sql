-- ============================================================================
-- Migration: Barangay Hall positions (job titles)
-- Date: 2026-08-07
-- Requirement: BARANGAY_CONNECT_REQUIREMENTS.md §9 (User Roles), §11 (Barangay-
--              Specific Assignment), §10 (personnel analytics)
-- ============================================================================
--
-- DESIGN: `role` stays the PERMISSION TIER. `position` is the JOB TITLE.
--
--   role      = superadmin | admin | resident | non_resident   (who can do what)
--   position  = secretary | captain | tanod | staff | NULL     (what they are)
--
-- This is additive on purpose. Every existing RLS policy keys off `role` via
-- get_user_role() and keeps working with zero changes — no policy rewrites, no
-- risk of locking anyone out. Existing 'admin' accounts stay valid; they simply
-- have position = NULL until someone assigns them one.
--
-- SCOPE NOTE: There is deliberately no 'police' or 'fire' position. Contacting
-- PNP / BFP is the barangay hall's job, done outside this system. Every role in
-- this app is barangay hall personnel.
--
-- Safe to re-run (idempotent).
-- ============================================================================

-- 1. Add the position column ------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS position TEXT;

-- 2. Constrain it to known values -------------------------------------------
-- Dropped first so re-running with a changed value list works cleanly.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_position_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_position_check
  CHECK (
    position IS NULL
    OR position IN ('secretary', 'captain', 'tanod', 'staff')
  );

-- 3. Index for per-barangay roster lookups and personnel counts --------------
CREATE INDEX IF NOT EXISTS idx_profiles_position
  ON public.profiles(position)
  WHERE position IS NOT NULL;

-- Composite: "who are the tanods in Barangay X" — the assignment query.
CREATE INDEX IF NOT EXISTS idx_profiles_barangay_position
  ON public.profiles(barangay_id, position)
  WHERE position IS NOT NULL;

-- 4. Guard: only staff-tier accounts may hold a position --------------------
-- Prevents a resident from being given position = 'captain'.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_position_requires_staff_role;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_position_requires_staff_role
  CHECK (
    position IS NULL
    OR role IN ('admin', 'superadmin')
  );


-- ============================================================================
-- ASSIGNING POSITIONS (run manually as needed)
-- ============================================================================
-- Promote an existing official to Secretary:
--
--   UPDATE public.profiles
--   SET position = 'secretary'
--   WHERE email = 'secretary-email@example.com';
--
-- Valid values: 'secretary', 'captain', 'tanod', 'staff'
--
-- NOTE: the account must already have role = 'admin' (or 'superadmin'), or the
-- profiles_position_requires_staff_role constraint will reject the update.
-- Promote the role first if needed:
--
--   UPDATE public.profiles
--   SET role = 'admin', position = 'tanod', is_verified = true
--   WHERE email = 'tanod-email@example.com';


-- ============================================================================
-- VERIFY
-- ============================================================================
-- Personnel roster per barangay (feeds §10 "personnel at the Barangay Hall"):
--
--   SELECT b.name AS barangay, p.position, COUNT(*) AS headcount
--   FROM public.profiles p
--   LEFT JOIN public.barangays b ON b.id = p.barangay_id
--   WHERE p.position IS NOT NULL
--   GROUP BY b.name, p.position
--   ORDER BY b.name, p.position;
