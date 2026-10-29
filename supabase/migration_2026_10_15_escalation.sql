-- ============================================================================
-- Automatic escalation of unanswered reports  (panel revision #6)
-- ============================================================================
--
-- THE PROBLEM THIS SOLVES
-- The app already *detected* a late report: a badge on the incident card, an
-- "overdue" count in analytics. But every one of those checks ran on an
-- official's phone, when they opened the app. An official who never opens the
-- app is exactly the one who is not responding — so for that case nothing
-- fired. Detection that depends on the late person looking is not escalation.
--
-- WHAT THIS ADDS
-- A pg_cron job, running inside the database every 15 minutes, with no app and
-- no phone involved. For every open report it works out how far past its
-- response time it is, and when it crosses a line it writes a notification to
-- the next person up the chain:
--
--   Level 1  REMINDER   the official handling it  (or, if nobody has taken it,
--                       the barangay Secretary and Captain)
--   Level 2  OVERDUE    the handling official AND the barangay Secretary and
--                       Captain
--   Level 3  CITY       the city administrator (superadmin), with the
--                       Secretary and Captain kept informed
--
-- WHEN EACH LEVEL FIRES — measured from when the report was filed, using the
-- same lines as the app's SLA badge (lib/utils/helpers.dart: slaStatus):
--
--   waiting for someone to take it   (pending, verified)         12h / 24h / 48h
--   being handled                    (assigned, in_progress,
--                                     responding, on_scene)       24h / 48h / 72h
--
-- Level 3 is always 24 hours after "overdue": long enough that a supervisor has
-- had a full day to act, short enough that a report cannot sit for a week.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   * It does NOT change the report's severity. Severity says how dangerous the
--     thing is and is fixed by its category; lateness says how badly the
--     response is failing. Folding one into the other would make the severity
--     charts lie and let a stale noise complaint outrank a live emergency.
--     Escalation is recorded separately, in incident_escalations.
--   * It does NOT touch the incident row. An UPDATE would bump updated_at, and
--     the "is this case finished?" prompt measures from updated_at — escalating
--     a case would silently reset that clock.
--
-- Safe to run more than once. Requires the pg_cron extension (see step 4).
-- ============================================================================


-- ── 1. History: which level each report has reached, and who was told ───────
-- Doubles as the dedupe (a level is only ever sent once per report) and as the
-- audit trail, since audit_logs.user_id is NOT NULL and a scheduled job has no
-- user to attribute an action to.
CREATE TABLE IF NOT EXISTS public.incident_escalations (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid        NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
  level       smallint    NOT NULL CHECK (level BETWEEN 1 AND 3),
  recipients  integer     NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (incident_id, level)
);

CREATE INDEX IF NOT EXISTS incident_escalations_incident_idx
  ON public.incident_escalations (incident_id);

ALTER TABLE public.incident_escalations ENABLE ROW LEVEL SECURITY;

-- Officials read their own barangay's; the superadmin reads all. Nobody can
-- write: only the SECURITY DEFINER job below does.
DROP POLICY IF EXISTS "Officials read escalations" ON public.incident_escalations;
CREATE POLICY "Officials read escalations"
  ON public.incident_escalations FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'superadmin'
    OR (
      get_user_role() = 'admin'
      AND EXISTS (
        SELECT 1 FROM public.incidents i
        WHERE i.id = incident_escalations.incident_id
          AND i.barangay_id = get_user_barangay()
      )
    )
  );


-- ── 2. The rule: which level has this report reached? ───────────────────────
-- A pure function of status, age and the clock, so it can be tested on its own
-- (see the self-check at the bottom) and read in one place.
CREATE OR REPLACE FUNCTION public.escalation_level_for(
  p_status     text,
  p_created_at timestamptz,
  p_now        timestamptz DEFAULT now()
)
RETURNS smallint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (
    CASE
      WHEN p_status IN ('resolved', 'closed', 'flagged') THEN 0
      WHEN t.hours >= (t.warn * 2 + 24) THEN 3
      WHEN t.hours >= (t.warn * 2)      THEN 2
      WHEN t.hours >= t.warn            THEN 1
      ELSE 0
    END
  )::smallint
  FROM (
    SELECT
      extract(epoch FROM (p_now - p_created_at)) / 3600.0 AS hours,
      CASE WHEN p_status IN ('pending', 'verified') THEN 12 ELSE 24 END AS warn
  ) t;
$$;


-- ── 3. The job ──────────────────────────────────────────────────────────────
-- Returns how many reports were escalated on this run.
CREATE OR REPLACE FUNCTION public.escalate_overdue_incidents()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER            -- writes other users' notification rows
SET search_path = public
AS $$
DECLARE
  inc     RECORD;
  v_level smallint;
  v_hours integer;
  v_sent  integer;
  v_total integer := 0;
  v_title text;
  v_body  text;
BEGIN
  FOR inc IN
    SELECT
      i.id,
      i.barangay_id,
      i.category,
      i.status,
      i.assigned_to,
      i.created_at,
      COALESCE(b.name, 'a barangay') AS barangay_name,
      COALESCE(
        (SELECT max(e.level) FROM public.incident_escalations e
          WHERE e.incident_id = i.id),
        0
      ) AS done_level
    FROM public.incidents i
    LEFT JOIN public.barangays b ON b.id = i.barangay_id
    WHERE i.status NOT IN ('resolved', 'closed', 'flagged')
      -- Reports older than two weeks went through every level long ago. Without
      -- this, the first run would send a city-level alert for every ancient
      -- test report still sitting open.
      AND i.created_at >= now() - interval '14 days'
  LOOP
    v_level := public.escalation_level_for(inc.status, inc.created_at);

    -- Not yet at a new line. A level is only ever sent once per report, and if
    -- the job was paused and a report jumped two lines, only the highest is
    -- sent — three alerts at once about the same report would be noise.
    CONTINUE WHEN v_level <= inc.done_level;

    v_hours := floor(extract(epoch FROM (now() - inc.created_at)) / 3600)::integer;

    IF v_level = 1 THEN
      v_title := 'Report awaiting a response';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' has had no '
                 || 'resolution for ' || v_hours || ' hours. Please act on it.';
    ELSIF v_level = 2 THEN
      v_title := 'Report overdue';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' is overdue ('
                 || v_hours || ' hours). Supervisors have been alerted.';
    ELSE
      v_title := 'Escalated to the City Administrator';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' is still '
                 || 'unresolved after ' || v_hours || ' hours and needs '
                 || 'city-level intervention.';
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read)
    SELECT p.id, v_title, v_body, 'escalation', inc.id, FALSE
    FROM public.profiles p
    WHERE p.is_locked = FALSE
      AND (
        -- The official handling it, at every level.
        p.id = inc.assigned_to
        -- The barangay's supervisors: from level 2 up, and already at level 1
        -- when nobody has taken the report (there is no one else to remind).
        OR (
          p.role = 'admin'
          AND p.barangay_id = inc.barangay_id
          AND p.position IN ('secretary', 'captain')
          AND (v_level >= 2 OR inc.assigned_to IS NULL)
        )
        -- The city administrator, only once it has reached the city.
        OR (p.role = 'superadmin' AND v_level >= 3)
      );
    GET DIAGNOSTICS v_sent = ROW_COUNT;

    -- A barangay with no Secretary or Captain recorded, and nobody assigned,
    -- would otherwise escalate to no one. Fall back to every official there:
    -- an alert that reaches nobody is worse than one that reaches too many.
    IF v_sent = 0 THEN
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read)
      SELECT p.id, v_title, v_body, 'escalation', inc.id, FALSE
      FROM public.profiles p
      WHERE p.is_locked = FALSE
        AND p.role = 'admin'
        AND p.barangay_id = inc.barangay_id;
      GET DIAGNOSTICS v_sent = ROW_COUNT;
    END IF;

    INSERT INTO public.incident_escalations (incident_id, level, recipients)
    VALUES (inc.id, v_level, v_sent)
    ON CONFLICT (incident_id, level) DO NOTHING;

    v_total := v_total + 1;
  END LOOP;

  RETURN v_total;
END;
$$;

-- SECURITY DEFINER means "runs with the owner's rights", so anyone who could
-- call it over the API could make it write notifications to every official.
-- Only the scheduler (which runs as the database owner) needs to.
REVOKE ALL ON FUNCTION public.escalate_overdue_incidents() FROM PUBLIC, anon, authenticated;


-- ── 4. Schedule it ──────────────────────────────────────────────────────────
-- If CREATE EXTENSION is refused, enable it from the dashboard instead:
--   Database -> Extensions -> pg_cron -> enable   (then re-run this file)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Idempotent: drop any earlier schedule of the same name before re-adding it.
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'escalate-overdue-incidents';

SELECT cron.schedule(
  'escalate-overdue-incidents',
  '*/15 * * * *',
  $cron$SELECT public.escalate_overdue_incidents();$cron$
);


-- ── 5. Self-check: the rule must agree with the app's SLA badge ─────────────
-- Runs as part of this file. If a boundary is wrong the whole migration stops
-- with a message naming the case, instead of silently escalating at the wrong
-- time.
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      -- waiting for someone to take it: 12 / 24 / 48
      ('pending',     11, 0), ('pending',     12, 1), ('pending',     23, 1),
      ('pending',     24, 2), ('pending',     47, 2), ('pending',     48, 3),
      ('verified',    12, 1), ('verified',    24, 2),
      -- being handled: 24 / 48 / 72
      ('assigned',    23, 0), ('assigned',    24, 1), ('responding',  47, 1),
      ('responding',  48, 2), ('on_scene',    71, 2), ('on_scene',    72, 3),
      ('in_progress', 24, 1), ('in_progress', 72, 3),
      -- finished or set aside: never escalate
      ('resolved',   500, 0), ('closed',     500, 0), ('flagged',    500, 0)
    ) AS t(status, hours, expected)
  LOOP
    IF public.escalation_level_for(
         c.status, now() - make_interval(hours => c.hours)
       ) <> c.expected THEN
      RAISE EXCEPTION
        'escalation_level_for(%, % h) returned %, expected %',
        c.status, c.hours,
        public.escalation_level_for(c.status, now() - make_interval(hours => c.hours)),
        c.expected;
    END IF;
  END LOOP;
END;
$$;


-- ── VERIFY (run these yourself afterwards) ──────────────────────────────────
-- 1. The job is scheduled and running:
--      SELECT jobname, schedule, active FROM cron.job;
--      SELECT status, return_message, start_time
--        FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
--
-- 2. Run it once by hand (as the database owner, in the SQL editor):
--      SELECT public.escalate_overdue_incidents();
--
-- 3. See what it did:
--      SELECT i.category, e.level, e.recipients, e.created_at
--      FROM public.incident_escalations e
--      JOIN public.incidents i ON i.id = e.incident_id
--      ORDER BY e.created_at DESC;
--
--      SELECT n.title, p.email, p.position, n.created_at
--      FROM public.notifications n
--      JOIN public.profiles p ON p.id = n.user_id
--      WHERE n.type = 'escalation'
--      ORDER BY n.created_at DESC;
