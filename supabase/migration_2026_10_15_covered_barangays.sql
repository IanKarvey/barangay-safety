-- Incident counts per barangay, for the "Covered Barangays" card
-- (panel revision #4: show the covered areas, highlighting the barangays with
-- the highest incident reports).
--
-- WHY A FUNCTION RATHER THAN QUERYING `incidents`
-- A resident can only read their own reports, which is right. Ranking five
-- barangays by incident count needs totals across everyone's reports. This
-- function is SECURITY DEFINER so it can count them, and returns ONLY the
-- barangay name and a number — no report, no reporter, no location. A count is
-- the one thing here that is safe for any signed-in person to see.
--
-- Flagged reports are left out: they are false or abusive reports that were set
-- aside, and counting them would make a barangay look busier than it is.
--
-- Safe to run more than once. The app works without it (the card simply shows
-- the covered barangays without counts).

CREATE OR REPLACE FUNCTION public.covered_barangay_stats()
RETURNS TABLE (barangay_id uuid, name text, incident_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.id,
    b.name,
    COUNT(i.id) FILTER (WHERE i.status <> 'flagged') AS incident_count
  FROM public.barangays b
  LEFT JOIN public.incidents i ON i.barangay_id = b.id
  GROUP BY b.id, b.name
  ORDER BY incident_count DESC, b.name;
$$;

-- Signed-in users only; the anonymous key has no business counting reports.
REVOKE ALL ON FUNCTION public.covered_barangay_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.covered_barangay_stats() TO authenticated;

-- ── Verify (run as yourself in the SQL editor) ──────────────────────────────
--   SELECT * FROM public.covered_barangay_stats();
