-- ============================================================================
-- Migration: Assign a barangay official to a non-resident report
-- Date: 2026-08-10
-- Requirement: §1 — the reporter should know who is coming and be able to
--              call them.
-- ============================================================================
--
-- PROBLEM
--   A non-resident could see that help was dispatched, but not WHO. They had
--   no name and no way to ring the person actually coming to them — only the
--   shared barangay hotline.
--
-- APPROACH
--   Assign an official to the session, then expose that one official's
--   contact details to that one reporter through a SECURITY DEFINER function.
--
--   A join won't work here: the reporter is an anonymous auth user with no
--   profiles row, so RLS denies them every profile. And widening profile
--   access would expose every official's personal number to every visitor.
--   The function returns exactly one official — the one assigned to the
--   caller's own session — and nothing else.
--
-- Safe to re-run (idempotent).
-- ============================================================================

ALTER TABLE public.non_resident_sessions
  ADD COLUMN IF NOT EXISTS assigned_official_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_nrs_assigned_official
  ON public.non_resident_sessions(assigned_official_id)
  WHERE assigned_official_id IS NOT NULL;


-- ── Reporter-facing lookup ──────────────────────────────────────────────────
-- Returns the official assigned to the CALLER'S OWN session, or nothing.
-- Scoped by auth.uid() so a reporter can never read anyone else's responder.
CREATE OR REPLACE FUNCTION public.get_my_assigned_official()
RETURNS TABLE (
  id        UUID,
  full_name TEXT,
  "position"  TEXT,
  phone     TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.full_name, p.position, p.phone
  FROM public.non_resident_sessions s
  JOIN public.profiles p ON p.id = s.assigned_official_id
  WHERE s.auth_user_id = auth.uid()
    AND s.status NOT IN ('completed', 'disregarded')
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_assigned_official() TO authenticated;


-- ── Officials available to assign ───────────────────────────────────────────
-- Used by the officials' queue screen to populate the assign picker.
CREATE OR REPLACE FUNCTION public.get_assignable_officials(p_barangay_id UUID)
RETURNS TABLE (
  id        UUID,
  full_name TEXT,
  "position"  TEXT,
  phone     TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.full_name, p.position, p.phone
  FROM public.profiles p
  WHERE p.barangay_id = p_barangay_id
    AND p.role IN ('admin', 'superadmin')
    AND p.is_locked = FALSE
  ORDER BY (p.position = 'tanod') DESC NULLS LAST, p.full_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_assignable_officials(UUID) TO authenticated;


-- ============================================================================
-- VERIFY
-- ============================================================================
--   SELECT * FROM public.get_assignable_officials(
--     (SELECT barangay_id FROM public.profiles WHERE email = 'official@example.com')
--   );
