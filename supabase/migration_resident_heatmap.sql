-- ============================================================================
-- Migration: Let residents see incident density in their barangay
-- Date: 2026-08-09
-- Requirement: §16 Heat Map — extended to residents so they can be warned
--              which areas report the most incidents.
-- ============================================================================
--
-- PROBLEM
--   RLS restricts residents to `reporter_id = auth.uid()`, so a resident
--   opening the heat map sees only their OWN reports — useless as a warning.
--
-- WHY NOT JUST WIDEN THE POLICY
--   Letting residents SELECT every incident in their barangay would expose
--   reporter names, descriptions, addresses and photo URLs. A neighbour could
--   read who reported domestic violence at which address. That is a serious
--   privacy failure in a barangay-scale community where everyone knows
--   everyone.
--
-- APPROACH
--   A SECURITY DEFINER function returning ONLY what a density map needs:
--   coordinates, severity, category, date. No reporter, no description, no
--   address, no media.
--
--   Coordinates are rounded to ~3 decimal places (roughly 100m) before being
--   returned. A heat map communicates "this area has a pattern", which does
--   not require pinpointing a house — and unrounded coordinates on a
--   domestic-violence or drug-related report would effectively publish a
--   specific home to the whole barangay.
--
-- Safe to re-run (idempotent).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_incident_heat_points(
  p_barangay_id UUID DEFAULT NULL,
  p_days INT DEFAULT NULL
)
RETURNS TABLE (
  lat            DOUBLE PRECISION,
  lng            DOUBLE PRECISION,
  severity_level INT,
  category       TEXT,
  created_at     TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ROUND(i.latitude::numeric,  3)::double precision  AS lat,
    ROUND(i.longitude::numeric, 3)::double precision  AS lng,
    i.severity_level,
    i.category,
    i.created_at
  FROM public.incidents i
  WHERE (p_barangay_id IS NULL OR i.barangay_id = p_barangay_id)
    AND (p_days IS NULL OR i.created_at > NOW() - (p_days || ' days')::interval)
    -- Flagged reports are unverified or false; showing them would scare
    -- residents about incidents that never happened.
    AND i.status <> 'flagged';
$$;

-- Any signed-in user may call it. The function itself is the privacy boundary:
-- it can only ever return coordinates, severity, category and date.
GRANT EXECUTE ON FUNCTION public.get_incident_heat_points(UUID, INT)
  TO authenticated;


-- ============================================================================
-- VERIFY
-- ============================================================================
--   SELECT * FROM public.get_incident_heat_points();
--   SELECT * FROM public.get_incident_heat_points(NULL, 90);
--
-- Confirm no identifying columns are returned — the result should contain
-- exactly: lat, lng, severity_level, category, created_at.
