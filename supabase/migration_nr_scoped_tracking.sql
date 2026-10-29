-- ============================================================================
-- Migration: Scope responder tracking to the assigned reporter only
-- Date: 2026-08-10
-- Requirement: §1 — privacy of officials' live location
-- ============================================================================
--
-- PROBLEM
--   `responder_locations` returned EVERY official sharing in a barangay, so
--   any reporter could watch every official move — including one travelling
--   to somebody else's emergency, or simply going about their day. That is
--   effectively public GPS tracking of barangay staff, and it leaks the
--   existence and rough location of other people's incidents.
--
-- FIX
--   A reporter sees exactly ONE responder: the official assigned to their own
--   session. Enforced in the database rather than by filtering client-side,
--   so the data never reaches the device in the first place.
--
--   Sharing also switches itself off when an official's last open assignment
--   closes — an official should not keep broadcasting because someone forgot
--   to toggle it, and a resolved reporter must not be able to keep watching.
--
-- Safe to re-run (idempotent).
-- ============================================================================

-- ── Reporter's own responder, with position ─────────────────────────────────
-- Replaces the reporter's use of `responder_locations` entirely.
-- Scoped by auth.uid(); returns at most one row.
CREATE OR REPLACE FUNCTION public.get_my_assigned_official()
RETURNS TABLE (
  id               UUID,
  full_name        TEXT,
  "position"       TEXT,
  phone            TEXT,
  last_lat         DOUBLE PRECISION,
  last_lng         DOUBLE PRECISION,
  last_location_at TIMESTAMPTZ,
  is_sharing       BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.full_name,
    p.position,
    p.phone,
    -- Coordinates only while they are actively sharing AND the report is
    -- still open. A closed report must not keep revealing where staff are.
    CASE WHEN p.is_sharing_location THEN p.last_lat END,
    CASE WHEN p.is_sharing_location THEN p.last_lng END,
    CASE WHEN p.is_sharing_location THEN p.last_location_at END,
    p.is_sharing_location
  FROM public.non_resident_sessions s
  JOIN public.profiles p ON p.id = s.assigned_official_id
  WHERE s.auth_user_id = auth.uid()
    AND s.status NOT IN ('completed', 'disregarded')
    AND p.is_locked = FALSE
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_assigned_official() TO authenticated;


-- ── Stop sharing when the last assignment closes ────────────────────────────
CREATE OR REPLACE FUNCTION public.stop_sharing_when_done()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('completed', 'disregarded')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.assigned_official_id IS NOT NULL THEN

    -- Only if this was their LAST open assignment — an official handling two
    -- incidents must keep broadcasting for the other one.
    IF NOT EXISTS (
      SELECT 1 FROM public.non_resident_sessions o
      WHERE o.assigned_official_id = NEW.assigned_official_id
        AND o.id <> NEW.id
        AND o.status NOT IN ('completed', 'disregarded')
    ) THEN
      UPDATE public.profiles
      SET is_sharing_location = FALSE,
          last_lat = NULL,
          last_lng = NULL,
          last_location_at = NULL
      WHERE id = NEW.assigned_official_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stop_sharing_when_done
  ON public.non_resident_sessions;

CREATE TRIGGER trg_stop_sharing_when_done
  AFTER UPDATE ON public.non_resident_sessions
  FOR EACH ROW EXECUTE FUNCTION public.stop_sharing_when_done();


-- ── Lock down the broad view ────────────────────────────────────────────────
-- Officials may still see each other (useful for coordination); reporters no
-- longer read this at all — they use get_my_assigned_official().
CREATE OR REPLACE VIEW public.responder_locations AS
  SELECT
    p.id,
    p.full_name,
    p.position,
    p.barangay_id,
    p.last_lat,
    p.last_lng,
    p.last_location_at,
    p.role
  FROM public.profiles p
  WHERE p.is_sharing_location = TRUE
    AND p.last_lat IS NOT NULL
    AND p.last_lng IS NOT NULL
    AND p.is_locked = FALSE
    -- Anonymous reporters have no profiles row, so this excludes them while
    -- leaving officials' coordination view intact.
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid()
        AND me.role IN ('admin', 'superadmin')
    );

GRANT SELECT ON public.responder_locations TO authenticated;


-- ============================================================================
-- VERIFY
-- ============================================================================
--   SELECT * FROM public.get_my_assigned_official();   -- as the reporter
--   SELECT * FROM public.responder_locations;          -- officials only now
