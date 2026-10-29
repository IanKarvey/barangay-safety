-- ============================================================================
-- Migration: Scope comment reads to the people involved in the incident
-- Date: 2026-08-11
-- ============================================================================
--
-- PROBLEM
--   The SELECT policy on incident_comments is `USING (true)`: every signed-in
--   user can read every comment thread in the system. That includes anonymous
--   non-resident sessions, which authenticate through Supabase anonymous auth
--   and therefore count as `authenticated`. Comment threads carry names,
--   addresses and case details, so this is a real disclosure.
--
-- FIX
--   Mirror the shape already used by `incident_media`: an EXISTS check against
--   `incidents`. The subquery is itself subject to the incidents RLS policies,
--   which is what does the barangay scoping — an admin of barangay A cannot
--   see the incident row for barangay B, so EXISTS is false and the comments
--   are denied. Reporters match on reporter_id.
--
--   Anonymous non-residents have no profiles row (see
--   migration_anon_user_trigger_fix.sql), so get_user_role() returns NULL for
--   them and they own no incidents — they end up with no comment access at
--   all, which is correct: their flow uses non_resident_sessions, not
--   incident_comments.
--
-- SAFETY
--   Wrapped in a transaction. Postgres DDL is transactional, so a failure
--   rolls the DROP back too — it cannot leave the table with no read policy
--   and silently break every comment thread.
--
--   Run STEP 0 FIRST. Dropping a policy by the wrong name silently succeeds
--   and leaves the hole wide open while looking like it worked.
--
-- Safe to re-run (idempotent).
-- ============================================================================


-- ── STEP 0: look at what is actually there ─────────────────────────────────
-- Run this ALONE first and read the output. You are looking for a SELECT
-- policy whose `qual` is `true`. Note its exact policyname.

SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'incident_comments'
ORDER BY cmd, policyname;


-- ── STEP 1: replace the permissive read policy ─────────────────────────────
-- STEP 0 was run on 2026-08-11. Actual policies found:
--
--   Officials can post comments             INSERT
--   Residents can comment on own incidents  INSERT
--   Authenticated users can read comments   SELECT  qual = true   <- the hole
--   Residents can read own incident comments SELECT  reporter check
--
-- Note there was NO select policy for officials. Officials could read
-- comments only because of the `true` policy, so dropping it alone would have
-- blanked every thread on the official side. The drop and the replacement
-- must land in the same transaction.
--
-- "Residents can read own incident comments" is deliberately left in place.
-- The policy below already covers residents, so it is redundant — but SELECT
-- policies are OR'd, so it stays as a fallback if this one has a flaw.

BEGIN;

DROP POLICY IF EXISTS "Authenticated users can read comments" ON public.incident_comments;
DROP POLICY IF EXISTS "Involved parties can read comments"    ON public.incident_comments;

CREATE POLICY "Involved parties can read comments"
  ON public.incident_comments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.incidents
      WHERE incidents.id = incident_comments.incident_id
        AND (
          incidents.reporter_id = auth.uid()
          OR get_user_role() IN ('admin', 'superadmin')
        )
    )
  );

-- The policy filters on this on every comment read, including every realtime
-- row delivered to a subscriber.
CREATE INDEX IF NOT EXISTS idx_incident_comments_incident_id
  ON public.incident_comments (incident_id);

COMMIT;


-- ── STEP 2: verify ─────────────────────────────────────────────────────────
-- Expect exactly one SELECT policy, named "Involved parties can read
-- comments", with a qual that is NOT `true`.

SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'incident_comments'
ORDER BY cmd, policyname;
