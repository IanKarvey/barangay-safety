-- ============================================================================
-- Flip the severity scale on existing data: 1↔4, 2↔3.
-- 2026-08-25
-- ============================================================================
--
-- ## Why
--
-- The scale was reversed in the app on 2026-08-25 at the owner's direction:
-- **4 is now Critical and 1 is Low**, where it used to be the other way round.
--
-- The code flip alone leaves every existing row lying. An incident stored as
-- `severity_level = 1` was filed as *Critical*; the new app renders it as
-- *Level 1: Low*, draws it as a small green pin, and leaves it out of the
-- dashboard's urgent counters. The reverse is worse: an old noise complaint
-- stored as 4 now reads as Critical, pulses red on the map, and — had it been
-- filed after this change — would have alerted the whole barangay hall.
--
-- ## ⚠️ THIS IS THE ONE MIGRATION THAT MUST NOT RUN TWICE
--
-- Every other migration in this folder is idempotent. This one is not, by
-- nature: `5 - level` applied twice returns the original value, silently
-- undoing itself. So it is guarded by a marker table and will refuse to run a
-- second time. Do not remove the guard, and do not "just run the UPDATE" by
-- hand.
--
-- Safe to run more than once *because of the guard* — repeat runs report
-- "already applied" and change nothing.
-- ============================================================================


-- ── The guard ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.applied_migrations (
  name        text PRIMARY KEY,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  note        text
);

COMMENT ON TABLE public.applied_migrations IS
  'One row per non-idempotent migration. Prevents a second run silently '
  'undoing the first.';


-- ── The flip ────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_name text := '2026_08_25_flip_severity_scale';
  v_rows bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM public.applied_migrations WHERE name = v_name) THEN
    RAISE NOTICE 'Severity flip already applied — skipping. Nothing changed.';
    RETURN;
  END IF;

  -- 5 - level maps 1→4, 2→3, 3→2, 4→1 in one pass.
  -- Rows outside 1..4 are left alone rather than clamped: an out-of-range
  -- value is a data problem to look at, not one to quietly rewrite.
  UPDATE public.incidents
  SET    severity_level = 5 - severity_level
  WHERE  severity_level BETWEEN 1 AND 4;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  INSERT INTO public.applied_migrations (name, note)
  VALUES (v_name, format('flipped %s incident rows: 1<->4, 2<->3', v_rows));

  RAISE NOTICE 'Severity flip applied to % incident rows.', v_rows;
END $$;


-- ============================================================================
-- Verification
-- ============================================================================

-- 1. Confirm it recorded as applied.
SELECT name, applied_at, note FROM public.applied_migrations
WHERE  name = '2026_08_25_flip_severity_scale';

-- 2. The distribution, in the NEW meaning. Sanity-check it against reality:
--    a barangay should have far more Low/Medium than Critical. If Critical
--    dominates, the flip may have run twice or not at all.
SELECT severity_level,
       CASE severity_level
         WHEN 4 THEN 'Critical'
         WHEN 3 THEN 'High'
         WHEN 2 THEN 'Medium'
         WHEN 1 THEN 'Low'
         ELSE 'OUT OF RANGE'
       END AS meaning,
       count(*) AS incidents
FROM   public.incidents
GROUP  BY severity_level
ORDER  BY severity_level DESC;

-- 3. Anything outside the scale — expect zero rows.
SELECT id, severity_level, category, created_at
FROM   public.incidents
WHERE  severity_level NOT BETWEEN 1 AND 4;

-- ============================================================================
-- Sense check against a category you can recognise. From now on the app sets
-- severity from the category, so new rows will always agree with this table:
--
--   Fire, Medical Emergency, Physical Assault, Domestic Violence  -> 4
--   Vehicular Accident, Theft / Robbery, Flooding, Drug-Related   -> 3
--   Suspicious Activity, Vandalism, Public Disturbance, Other     -> 2
--   Noise Disturbance                                             -> 1
--
-- Older rows were set by hand, so they will NOT all match — that is expected
-- and is not a fault of this migration.
-- ============================================================================
SELECT category, severity_level, count(*)
FROM   public.incidents
GROUP  BY category, severity_level
ORDER  BY category, severity_level DESC;
