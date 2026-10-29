-- ============================================================================
-- Three features, one migration  (panel revisions, 2026-10-20)
--
--   PART 1  Response-time tracking   status log, first-action stamps, metrics view
--   PART 2  Auto-escalation          5 / 10 / 15 minute tiers for unanswered reports
--   PART 3  Tutorial usage log
--
-- Run the whole file once in the Supabase SQL Editor. It is safe to run again.
-- It needs PostgreSQL 15 or newer (the metrics view uses security_invoker so a
-- barangay admin can only ever read their own barangay). It stops with a clear
-- message if the database is older.
--
-- WHAT CHANGES FOR THE EXISTING ESCALATION JOB
-- migration_2026_10_15_escalation.sql escalated a *waiting* report after
-- 12 / 24 / 48 hours. That was too slow to protect someone who is waiting for
-- rescue, so waiting reports now escalate by minutes (PART 2) and the hour-based
-- job only watches reports that someone has already taken and not finished
-- (24 / 48 / 72 hours). A report is in exactly one of the two systems at a time,
-- so nobody is alerted twice for the same thing.
-- ============================================================================

DO $$
BEGIN
  IF current_setting('server_version_num')::int < 150000 THEN
    RAISE EXCEPTION
      'This migration needs PostgreSQL 15+ (found %). Upgrade the project in Supabase -> Settings -> Infrastructure first.',
      current_setting('server_version');
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 1 — RESPONSE-TIME TRACKING
-- ════════════════════════════════════════════════════════════════════════════
--
-- Field mapping (the spec's names -> what already exists, so nothing is stored twice):
--   submitted_at   = incidents.created_at   (DEFAULT now(): the SERVER's clock; the
--                                            app never sends it, so a wrong phone
--                                            clock cannot change it)
--   acknowledged_at= incidents.verified_at
--   assigned_at    = incidents.assigned_at
--   dispatched_at  = incidents.responding_at
--   on_scene_at, resolved_at, closed_at = unchanged
-- New columns below fill the gaps.

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS first_seen_at         timestamptz,
  ADD COLUMN IF NOT EXISTS first_action_at       timestamptz,
  ADD COLUMN IF NOT EXISTS first_action_by       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS escalation_stopped_at timestamptz,
  ADD COLUMN IF NOT EXISTS escalation_level      smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reminder_count        smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_reminder_at      timestamptz;

ALTER TABLE public.incidents
  DROP CONSTRAINT IF EXISTS incidents_escalation_level_check;
ALTER TABLE public.incidents
  ADD CONSTRAINT incidents_escalation_level_check
  CHECK (escalation_level BETWEEN 0 AND 3);

-- The escalation job scans only reports nobody has acted on.
CREATE INDEX IF NOT EXISTS idx_incidents_unanswered
  ON public.incidents (created_at)
  WHERE first_action_at IS NULL AND escalation_stopped_at IS NULL;


-- ── 1a. The status log: one row per status change, written by the database ──
-- Insert-only. The app cannot write it at all (no INSERT/UPDATE/DELETE policy and
-- the privileges are revoked), so a timestamp cannot be skipped or edited.
CREATE TABLE IF NOT EXISTS public.report_status_logs (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  report_id       uuid        NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
  from_status     text,
  to_status       text        NOT NULL,
  changed_by      uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  changed_by_name text,
  changed_by_role text,
  changed_at      timestamptz NOT NULL DEFAULT now(),
  remarks         text
);

CREATE INDEX IF NOT EXISTS idx_status_logs_report
  ON public.report_status_logs (report_id, changed_at);

ALTER TABLE public.report_status_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Officials read status logs" ON public.report_status_logs;
CREATE POLICY "Officials read status logs"
  ON public.report_status_logs FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'superadmin'
    OR (
      get_user_role() = 'admin'
      AND EXISTS (
        SELECT 1 FROM public.incidents i
        WHERE i.id = report_status_logs.report_id
          AND i.barangay_id = get_user_barangay()
      )
    )
  );

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.report_status_logs FROM PUBLIC, anon, authenticated;

-- Belt and braces: even a privileged connection cannot rewrite history.
CREATE OR REPLACE FUNCTION public.status_logs_are_append_only()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'report_status_logs is insert-only';
END $$;

DROP TRIGGER IF EXISTS trg_status_logs_no_update ON public.report_status_logs;
CREATE TRIGGER trg_status_logs_no_update
  BEFORE UPDATE ON public.report_status_logs
  FOR EACH ROW EXECUTE FUNCTION public.status_logs_are_append_only();


-- ── 1b. Who did it, in words a report can print ─────────────────────────────
-- 'captain', 'tanod', ... when the account has a barangay position; otherwise
-- the plain role ('resident', 'admin', 'superadmin').
CREATE OR REPLACE FUNCTION public.actor_label(p_user uuid)
RETURNS TABLE (name text, role_label text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.full_name, COALESCE(p.position, p.role)
  FROM public.profiles p WHERE p.id = p_user;
$$;
REVOKE ALL ON FUNCTION public.actor_label(uuid) FROM PUBLIC, anon, authenticated;


-- ── 1c. Log every status change (and the first row, "pending") ───────────────
CREATE OR REPLACE FUNCTION public.log_incident_status_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid;
  v_name  text;
  v_role  text;
BEGIN
  -- A logging fault must never stop a resident filing a report or an official
  -- updating one: during an emergency the action matters more than the record.
  -- A failure is raised as a WARNING in the database log so it is not silent.
  BEGIN
    IF TG_OP = 'INSERT' THEN
      v_actor := NEW.reporter_id;
      IF v_actor IS NOT NULL THEN
        SELECT a.name, a.role_label INTO v_name, v_role FROM public.actor_label(v_actor) a;
      ELSE
        v_role := 'non_resident';   -- reported through an anonymous session
      END IF;
      INSERT INTO public.report_status_logs
        (report_id, from_status, to_status, changed_by, changed_by_name, changed_by_role, changed_at)
      VALUES (NEW.id, NULL, NEW.status, v_actor, v_name, v_role, NEW.created_at);
      RETURN NEW;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_actor := auth.uid();
      IF v_actor IS NOT NULL THEN
        SELECT a.name, a.role_label INTO v_name, v_role FROM public.actor_label(v_actor) a;
      END IF;
      INSERT INTO public.report_status_logs
        (report_id, from_status, to_status, changed_by, changed_by_name, changed_by_role, changed_at, remarks)
      VALUES (
        NEW.id, OLD.status, NEW.status, v_actor, v_name, v_role, now(),
        CASE WHEN NEW.status IN ('resolved', 'closed') THEN NEW.resolution_notes END
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'status log failed for incident %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_log_incident_insert ON public.incidents;
CREATE TRIGGER trg_log_incident_insert
  AFTER INSERT ON public.incidents
  FOR EACH ROW EXECUTE FUNCTION public.log_incident_status_change();

DROP TRIGGER IF EXISTS trg_log_incident_status ON public.incidents;
CREATE TRIGGER trg_log_incident_status
  AFTER UPDATE ON public.incidents
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.log_incident_status_change();


-- ── 1d. The first official action stops the escalation clock ────────────────
-- "Action" = the status moves, or someone is assigned, or an official writes to
-- the resident (1e). Opening the report is NOT an action (1f logs it separately).
-- Runs in the database, so it cannot be skipped by any client.
CREATE OR REPLACE FUNCTION public.stamp_incident_first_action()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.first_action_at IS NULL AND NEW.first_action_at IS NULL AND (
       NEW.status IS DISTINCT FROM OLD.status
       OR (NEW.assigned_to IS NOT NULL AND NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
     )
  THEN
    NEW.first_action_at       := now();
    NEW.first_action_by       := COALESCE(auth.uid(), NEW.assigned_to);
    NEW.escalation_stopped_at := now();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_incident_first_action ON public.incidents;
CREATE TRIGGER trg_incident_first_action
  BEFORE UPDATE ON public.incidents
  FOR EACH ROW EXECUTE FUNCTION public.stamp_incident_first_action();


-- ── 1e. A message from an official to the resident also counts as action ─────
CREATE OR REPLACE FUNCTION public.comment_counts_as_action()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.author_role IN ('admin', 'superadmin') THEN
    BEGIN
      UPDATE public.incidents
         SET first_action_at       = now(),
             first_action_by       = NEW.author_id,
             escalation_stopped_at = now()
       WHERE id = NEW.incident_id
         AND first_action_at IS NULL;
    EXCEPTION WHEN OTHERS THEN
      -- Posting the message matters more than the stamp.
      RAISE WARNING 'first-action stamp from comment failed for incident %: %', NEW.incident_id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_comment_counts_as_action ON public.incident_comments;
CREATE TRIGGER trg_comment_counts_as_action
  AFTER INSERT ON public.incident_comments
  FOR EACH ROW EXECUTE FUNCTION public.comment_counts_as_action();


-- ── 1f. "An official opened it" — recorded, but it does not stop anything ────
CREATE OR REPLACE FUNCTION public.mark_incident_seen(p_incident uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
  v_brgy uuid;
BEGIN
  SELECT role, barangay_id INTO v_role, v_brgy
    FROM public.profiles WHERE id = auth.uid() AND is_locked = FALSE;
  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') THEN RETURN; END IF;

  UPDATE public.incidents
     SET first_seen_at = now()
   WHERE id = p_incident
     AND first_seen_at IS NULL
     AND (v_role = 'superadmin' OR barangay_id = v_brgy);
END $$;

REVOKE ALL ON FUNCTION public.mark_incident_seen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_incident_seen(uuid) TO authenticated;


-- ── 1g. Atomic "I'm responding" ─────────────────────────────────────────────
-- Officials can volunteer to take a report: Secretary, Captain, and TANODS (who
-- are the ones on call after hours). Front-desk staff cannot: they answer and
-- read, they are not sent to a scene.
--
-- Pressing it means "I am on my way", so the report goes straight to
-- 'responding' (assigned_at is stamped too, so the response-time report has no
-- hole in it) and the resident is told.
--
-- THE TANOD'S FIRST-FIVE-MINUTES RULE, enforced here and not only on the
-- screen: for a report nobody has touched yet, the hall staff get the first
-- step (5 minutes in production, escalation_settings.step_seconds) to answer it;
-- a tanod's volunteer button is greyed until then and the database refuses an
-- early press ('too_early', with the seconds left). The rule does not apply once
-- someone at the hall has acted (verified it, for instance): then a responder is
-- exactly what the report needs.
--
-- Two officials tap at the same instant: the database serialises the two
-- UPDATEs, the second finds assigned_to already filled, matches no row, and is
-- told who got there first. No app-side check can do this reliably.
CREATE OR REPLACE FUNCTION public.claim_incident(p_incident uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_role text;
  v_brgy uuid;
  v_name text;
  v_pos  text;
  v_hit  uuid;
  v_step integer;
  v_left integer;
  inc    RECORD;
BEGIN
  SELECT role, barangay_id, full_name, position INTO v_role, v_brgy, v_name, v_pos
    FROM public.profiles WHERE id = v_uid AND is_locked = FALSE;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') OR v_pos = 'staff' THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'not_allowed');
  END IF;

  v_step := COALESCE((SELECT step_seconds FROM public.escalation_settings WHERE id), 300);

  UPDATE public.incidents
     SET assigned_to = v_uid,
         assigned_at = COALESCE(assigned_at, now()),
         status      = CASE WHEN status IN ('pending', 'verified', 'assigned')
                            THEN 'responding' ELSE status END,
         updated_at  = now()
   WHERE id = p_incident
     AND assigned_to IS NULL
     AND status NOT IN ('resolved', 'closed', 'flagged')
     AND (v_role = 'superadmin' OR barangay_id = v_brgy)
     AND (
          v_pos IS DISTINCT FROM 'tanod'
          OR first_action_at IS NOT NULL
          OR status <> 'pending'
          OR created_at <= now() - make_interval(secs => v_step)
     )
  RETURNING id INTO v_hit;

  IF v_hit IS NOT NULL THEN
    RETURN jsonb_build_object('claimed', true, 'by_name', v_name, 'by_role', COALESCE(v_pos, v_role));
  END IF;

  SELECT i.status, i.assigned_to, i.barangay_id, i.created_at INTO inc
    FROM public.incidents i WHERE i.id = p_incident;

  -- A tanod who pressed it inside the hall's first few minutes.
  IF FOUND AND v_pos = 'tanod'
     AND inc.assigned_to IS NULL
     AND inc.status NOT IN ('resolved', 'closed', 'flagged')
     AND inc.barangay_id = v_brgy
  THEN
    v_left := GREATEST(1, ceil(extract(epoch FROM
                (inc.created_at + make_interval(secs => v_step) - now())))::integer);
    RETURN jsonb_build_object('claimed', false, 'reason', 'too_early', 'seconds_left', v_left);
  END IF;

  -- Lost the race (or it was closed / is another barangay's): say who has it.
  SELECT p.full_name, COALESCE(p.position, p.role) INTO v_name, v_pos
    FROM public.incidents i
    JOIN public.profiles p ON p.id = i.assigned_to
   WHERE i.id = p_incident;

  RETURN jsonb_build_object(
    'claimed', false,
    'reason',  CASE WHEN v_name IS NULL THEN 'unavailable' ELSE 'already_handled' END,
    'by_name', v_name,
    'by_role', v_pos
  );
END $$;

REVOKE ALL ON FUNCTION public.claim_incident(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_incident(uuid) TO authenticated;


-- ── 1h. Server time, so a phone with a wrong clock can still show a right timer ─
CREATE OR REPLACE FUNCTION public.server_time()
RETURNS timestamptz LANGUAGE sql STABLE AS $$ SELECT now(); $$;
GRANT EXECUTE ON FUNCTION public.server_time() TO anon, authenticated;


-- ── 1i. Export log ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.export_logs (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_name   text,
  barangay_id uuid        REFERENCES public.barangays(id) ON DELETE SET NULL,
  format      text        NOT NULL CHECK (format IN ('xlsx', 'docx', 'csv')),
  filters     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  row_count   integer     NOT NULL DEFAULT 0,
  exported_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.export_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Officials log their own exports" ON public.export_logs;
CREATE POLICY "Officials log their own exports"
  ON public.export_logs FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid() AND get_user_role() IN ('admin', 'superadmin'));

DROP POLICY IF EXISTS "Read export log" ON public.export_logs;
CREATE POLICY "Read export log"
  ON public.export_logs FOR SELECT
  TO authenticated
  USING (get_user_role() = 'superadmin' OR user_id = auth.uid());

REVOKE UPDATE, DELETE, TRUNCATE ON public.export_logs FROM PUBLIC, anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 2 — AUTO-ESCALATION OF UNANSWERED REPORTS
-- ════════════════════════════════════════════════════════════════════════════

-- ── 2a. Settings: the interval lives in a table, not in code ────────────────
-- step_seconds = 300 is production (5 / 10 / 15 minutes). For a live demo or
-- testing, set it to 30 -> the tiers fire at 30 s / 60 s / 90 s:
--     UPDATE public.escalation_settings SET step_seconds = 30;
-- and put it back afterwards:
--     UPDATE public.escalation_settings SET step_seconds = 300;
-- started_at: reports filed before this moment are never auto-escalated, so
-- installing this does not fire alerts for old test reports.
CREATE TABLE IF NOT EXISTS public.escalation_settings (
  id           boolean     PRIMARY KEY DEFAULT TRUE CHECK (id),
  step_seconds integer     NOT NULL DEFAULT 300 CHECK (step_seconds BETWEEN 10 AND 3600),
  enabled      boolean     NOT NULL DEFAULT TRUE,
  started_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Working hours (Philippine time). Inside them a report's first alert goes to the
-- people who run the hall (Secretary, Captain, staff). Outside them — evenings,
-- nights and weekends — it goes to the Captain and the tanods, who are the ones
-- on call, and widens to everyone at the next tier. Defaults: 8:00 to 17:00,
-- Monday to Friday. Change with, for example:
--     UPDATE public.escalation_settings SET work_start_hour = 7, work_end_hour = 18;
--     UPDATE public.escalation_settings SET work_weekends = true;   -- hall opens Saturdays/Sundays too
ALTER TABLE public.escalation_settings
  ADD COLUMN IF NOT EXISTS work_start_hour smallint NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS work_end_hour   smallint NOT NULL DEFAULT 17,
  ADD COLUMN IF NOT EXISTS work_weekends   boolean  NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS max_reminders   smallint NOT NULL DEFAULT 12;

-- After tier 3 a report that STILL has no response keeps being announced, to
-- officials and to the resident, once every step (every 5 minutes), up to
-- max_reminders times (12 = one more hour) or until somebody acts.
ALTER TABLE public.escalation_settings
  DROP CONSTRAINT IF EXISTS escalation_settings_max_reminders_check;
ALTER TABLE public.escalation_settings
  ADD CONSTRAINT escalation_settings_max_reminders_check
  CHECK (max_reminders BETWEEN 0 AND 100);

ALTER TABLE public.escalation_settings
  DROP CONSTRAINT IF EXISTS escalation_settings_work_hours_check;
ALTER TABLE public.escalation_settings
  ADD CONSTRAINT escalation_settings_work_hours_check
  CHECK (work_start_hour BETWEEN 0 AND 23
         AND work_end_hour BETWEEN 1 AND 24
         AND work_start_hour < work_end_hour);

INSERT INTO public.escalation_settings (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.escalation_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone signed in reads escalation settings" ON public.escalation_settings;
CREATE POLICY "Anyone signed in reads escalation settings"
  ON public.escalation_settings FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "Superadmin edits escalation settings" ON public.escalation_settings;
CREATE POLICY "Superadmin edits escalation settings"
  ON public.escalation_settings FOR UPDATE TO authenticated
  USING (get_user_role() = 'superadmin')
  WITH CHECK (get_user_role() = 'superadmin');


-- ── 2b. Emergency contacts (the "last resort" numbers) ──────────────────────
-- barangay_id NULL = city-level, set by the SuperAdmin; used when a barangay has
-- none of its own. The app falls back to 911 when this table has nothing at all.
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  barangay_id  uuid        REFERENCES public.barangays(id) ON DELETE CASCADE,
  label        text        NOT NULL,
  category     text        NOT NULL CHECK (category IN ('police', 'hospital', 'rescue', 'fire', 'other')),
  phone_number text        NOT NULL,
  sort_order   integer     NOT NULL DEFAULT 0,
  is_active    boolean     NOT NULL DEFAULT TRUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_barangay
  ON public.emergency_contacts (barangay_id, sort_order);

ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Signed-in users read emergency contacts" ON public.emergency_contacts;
CREATE POLICY "Signed-in users read emergency contacts"
  ON public.emergency_contacts FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "Superadmin manages emergency contacts" ON public.emergency_contacts;
CREATE POLICY "Superadmin manages emergency contacts"
  ON public.emergency_contacts FOR ALL TO authenticated
  USING (get_user_role() = 'superadmin')
  WITH CHECK (get_user_role() = 'superadmin');

-- An admin edits their own barangay's numbers only - never the city-level ones.
DROP POLICY IF EXISTS "Admin manages own barangay contacts" ON public.emergency_contacts;
CREATE POLICY "Admin manages own barangay contacts"
  ON public.emergency_contacts FOR ALL TO authenticated
  USING (
    get_user_role() = 'admin'
    AND barangay_id IS NOT NULL
    AND barangay_id = get_user_barangay()
  )
  WITH CHECK (
    get_user_role() = 'admin'
    AND barangay_id IS NOT NULL
    AND barangay_id = get_user_barangay()
  );

-- City-level starting numbers: the same ones the referral pop-up already uses
-- (lib/config/app_config.dart). Police, Ambulance and Rescue come first; fire and
-- 911 follow. Ambulance and Rescue are both the CDRRMO (Lipa Rescue), who answer
-- medical calls here — there is no separate ambulance number. Only inserted into
-- an empty table, so editing them later is never undone by running this again.
--
-- The police number was supplied as "+649000000001" (+64 is New Zealand) and is
-- stored as +63 on the assumption that was a typo. Call it once to be sure.
INSERT INTO public.emergency_contacts (barangay_id, label, category, phone_number, sort_order)
SELECT NULL, v.label, v.category, v.phone, v.ord
FROM (VALUES
  ('Police (PNP Lipa)',          'police',   '+639000000001', 1),
  ('Ambulance (CDRRMO)',         'hospital', '+639000000002', 2),
  ('Rescue (CDRRMO Lipa)',       'rescue',   '+63437560217',  3),
  ('Fire (BFP Lipa)',            'fire',     '+63437574168',  4),
  ('National Emergency (911)',   'other',    '911',           5)
) AS v(label, category, phone, ord)
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts);


-- ── 2c. The escalation history ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.report_escalation_events (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id            uuid        NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
  level                smallint    NOT NULL CHECK (level BETWEEN 1 AND 3),
  triggered_at         timestamptz NOT NULL DEFAULT now(),
  notified_roles       text[]      NOT NULL DEFAULT '{}',
  notified_user_ids    uuid[]      NOT NULL DEFAULT '{}',
  resident_notified_at timestamptz,
  UNIQUE (report_id, level)         -- a report can never get the same level twice
);

CREATE INDEX IF NOT EXISTS idx_escalation_events_report
  ON public.report_escalation_events (report_id);

ALTER TABLE public.report_escalation_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Officials read escalation events" ON public.report_escalation_events;
CREATE POLICY "Officials read escalation events"
  ON public.report_escalation_events FOR SELECT TO authenticated
  USING (
    get_user_role() = 'superadmin'
    OR (
      get_user_role() = 'admin'
      AND EXISTS (
        SELECT 1 FROM public.incidents i
        WHERE i.id = report_escalation_events.report_id
          AND i.barangay_id = get_user_barangay()
      )
    )
  );

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.report_escalation_events FROM PUBLIC, anon, authenticated;


-- ── 2d. Notifications carry a small payload (level, role, name) ─────────────
-- The app uses it to show the message in the user's own language. The stored
-- title/body stay readable on their own (English, then Filipino) because the
-- push notification that reaches a closed app can only show text.
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS data jsonb;

-- The live notifications table was created in the dashboard, so its rules are not
-- in this repository. If it has a CHECK that limits `type` to a fixed list, the
-- new types below would be refused. The app treats `type` as free text, so any
-- such list is dropped rather than guessed at.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.notifications'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%type%'
  LOOP
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', c.conname);
    RAISE NOTICE 'dropped notifications constraint %', c.conname;
  END LOOP;
END $$;


-- ── 2e. The job ─────────────────────────────────────────────────────────────
-- Runs inside the database every 30 seconds: no app, no phone. For each report
-- nobody has acted on, it works out the tier from the SERVER clock and, when a
-- new tier is reached, tells the right people and the resident.
--
--   tier 1  step x 1   WORKING HOURS: Secretary, Captain and staff (not tanods)
--                      AFTER HOURS:   the Captain and the tanods, who are on call
--   tier 2  step x 2   everyone at the barangay hall, tanods included
--   tier 3  step x 3   everyone at the hall + the city administrator;
--                      the resident gets the emergency-numbers pop-up
--
-- "Working hours" come from escalation_settings (default 8:00-17:00, Monday to
-- Friday, Philippine time).
--
-- Idempotent: the UPDATE only moves a report forward while it is still
-- unanswered, and (report_id, level) is unique. If the job was paused and a
-- report crossed two lines, BOTH levels are logged but only the highest sends
-- messages (two alerts about the same report at once would just be noise).
CREATE OR REPLACE FUNCTION public.escalate_unanswered_reports()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s         public.escalation_settings%ROWTYPE;
  inc       RECORD;
  v_target  smallint;
  v_lvl     smallint;
  v_minutes integer;
  v_users   uuid[];
  v_roles   text[];
  v_title   text;
  v_body    text;
  v_res_t   text;
  v_res_b   text;
  v_total   integer := 0;
  v_local   timestamp;
  v_working boolean;
  rem       RECORD;
  v_n       smallint;
BEGIN
  SELECT * INTO s FROM public.escalation_settings WHERE id;
  IF NOT FOUND OR NOT s.enabled THEN RETURN 0; END IF;

  -- Is the hall open right now? Decided once per run, in Philippine time. The
  -- Philippines is UTC+8 all year with no daylight saving, so a fixed offset is
  -- exact and needs no time-zone database.
  v_local   := (now() AT TIME ZONE 'UTC') + interval '8 hours';
  v_working := (s.work_weekends OR extract(isodow FROM v_local) < 6)
               AND extract(hour FROM v_local) >= s.work_start_hour
               AND extract(hour FROM v_local) <  s.work_end_hour;

  FOR inc IN
    SELECT i.id, i.barangay_id, i.reporter_id, i.category, i.created_at, i.escalation_level,
           COALESCE(b.name, 'a barangay') AS barangay_name
      FROM public.incidents i
      LEFT JOIN public.barangays b ON b.id = i.barangay_id
     WHERE i.first_action_at IS NULL
       AND i.escalation_stopped_at IS NULL
       AND i.status = 'pending'
       AND i.escalation_level < 3
       AND i.created_at >= s.started_at
       -- A day is far past the last tier; anything older is stale, not urgent.
       AND i.created_at >= now() - interval '1 day'
     ORDER BY i.created_at
       FOR UPDATE OF i SKIP LOCKED
  LOOP
   -- One bad report must not stop the others from being escalated.
   BEGIN
    v_target := LEAST(3, floor(extract(epoch FROM (now() - inc.created_at)) / s.step_seconds))::smallint;
    CONTINUE WHEN v_target <= inc.escalation_level;

    -- Move forward only if it is STILL unanswered at this instant.
    UPDATE public.incidents
       SET escalation_level = v_target
     WHERE id = inc.id
       AND first_action_at IS NULL
       AND escalation_level < v_target;
    CONTINUE WHEN NOT FOUND;

    FOR v_lvl IN (inc.escalation_level + 1) .. v_target LOOP
      INSERT INTO public.report_escalation_events (report_id, level)
      VALUES (inc.id, v_lvl)
      ON CONFLICT (report_id, level) DO NOTHING;
    END LOOP;

    v_minutes := floor(extract(epoch FROM (now() - inc.created_at)) / 60)::integer;

    IF v_target = 1 THEN
      v_title := 'Report waiting for a response';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' has had no response for '
                 || v_minutes || ' min. Please take it now.';
      v_res_t := 'Our officials are busy / Abala pa ang mga official';
      v_res_b := 'We''re sorry, it looks like our barangay officials are currently busy. Please wait another 5 minutes.'
                 || E'\n' || 'Pasensya na po, mukhang abala pa ang aming mga barangay official. Mangyaring maghintay ng 5 minuto pa.';
    ELSIF v_target = 2 THEN
      v_title := 'Report still unanswered';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' is still unanswered after '
                 || v_minutes || ' min. The whole barangay hall is alerted - anyone can respond.';
      v_res_t := 'Alerting the whole barangay / Inaabisuhan ang buong barangay';
      v_res_b := 'We''re sorry for the inconvenience. We are now notifying the whole barangay so someone can take action quickly.'
                 || E'\n' || 'Paumanhin po sa abala. Inaabisuhan na namin ang buong barangay para may agad na tumugon.';
    ELSE
      v_title := 'UNATTENDED - last resort';
      v_body  := inc.category || ' in ' || inc.barangay_name || ' has had NO response for '
                 || v_minutes || ' min. Flagged Unattended. City administrator alerted.';
      v_res_t := 'Please call for help / Mangyaring tumawag';
      v_res_b := 'It seems our barangay is busy right now. Please call the emergency numbers in the app for immediate help.'
                 || E'\n' || 'Mukhang abala ang buong barangay ngayon. Mangyaring tumawag agad sa mga numerong nasa app.';
    END IF;

    -- Tier 1 goes to whoever is on duty: the people who run the hall in working
    -- hours, the Captain and tanods after hours. If the barangay has none of
    -- those recorded (no positions set) the audience widens rather than being
    -- empty.
    WITH ins AS (
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
      SELECT p.id, v_title, v_body, 'escalation', inc.id, FALSE,
             jsonb_build_object('kind', 'unanswered', 'level', v_target, 'minutes', v_minutes,
                                'after_hours', NOT v_working)
        FROM public.profiles p
       WHERE p.is_locked = FALSE
         AND (
              (p.role = 'admin' AND p.barangay_id = inc.barangay_id
               AND (
                    v_target >= 2
                    OR (v_working     AND COALESCE(p.position, '') <> 'tanod')
                    OR (NOT v_working AND p.position IN ('captain', 'tanod'))
               ))
           OR (p.role = 'superadmin' AND v_target >= 3)
         )
      RETURNING user_id
    )
    SELECT COALESCE(array_agg(user_id), '{}') INTO v_users FROM ins;

    IF cardinality(v_users) = 0 THEN
      WITH ins AS (
        INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
        SELECT p.id, v_title, v_body, 'escalation', inc.id, FALSE,
               jsonb_build_object('kind', 'unanswered', 'level', v_target, 'minutes', v_minutes)
          FROM public.profiles p
         WHERE p.is_locked = FALSE AND p.role = 'admin' AND p.barangay_id = inc.barangay_id
        RETURNING user_id
      )
      SELECT COALESCE(array_agg(user_id), '{}') INTO v_users FROM ins;
    END IF;

    v_roles := CASE WHEN v_target = 1 AND v_working     THEN ARRAY['secretary', 'captain', 'staff']
                    WHEN v_target = 1                   THEN ARRAY['captain', 'tanod']
                    WHEN v_target = 2 THEN ARRAY['secretary', 'captain', 'staff', 'tanod']
                    ELSE ARRAY['secretary', 'captain', 'staff', 'tanod', 'superadmin'] END;

    -- The resident (not available for anonymous non-resident reporters).
    IF inc.reporter_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = inc.reporter_id) THEN
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
      VALUES (inc.reporter_id, v_res_t, v_res_b, 'escalation_resident', inc.id, FALSE,
              jsonb_build_object('level', v_target));
    END IF;

    UPDATE public.report_escalation_events
       SET notified_user_ids    = v_users,
           notified_roles       = v_roles,
           resident_notified_at = CASE WHEN inc.reporter_id IS NOT NULL THEN now() END
     WHERE report_id = inc.id AND level = v_target;

    v_total := v_total + 1;
   EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'escalation failed for incident %: %', inc.id, SQLERRM;
   END;
  END LOOP;

  -- ── Still nobody after the last tier: keep both sides informed ─────────────
  -- Tier 3 is the end of the ladder, but a report with no response at 20 minutes
  -- is no less urgent than at 15. Every step after it, until somebody acts (or
  -- max_reminders is used up), the whole hall and the resident are told again,
  -- so neither side is left guessing. Reminder n is due (3 + n) steps after the
  -- report was filed: 20, 25, 30 ... minutes in production.
  FOR rem IN
    SELECT i.id, i.barangay_id, i.reporter_id, i.category, i.created_at, i.reminder_count,
           COALESCE(b.name, 'a barangay') AS barangay_name
      FROM public.incidents i
      LEFT JOIN public.barangays b ON b.id = i.barangay_id
     WHERE i.first_action_at IS NULL
       AND i.escalation_stopped_at IS NULL
       AND i.status = 'pending'
       AND i.escalation_level >= 3
       AND i.reminder_count < s.max_reminders
       AND i.created_at >= s.started_at
       AND i.created_at >= now() - interval '1 day'
       AND now() >= i.created_at + make_interval(secs => s.step_seconds * (4 + i.reminder_count))
     ORDER BY i.created_at
       FOR UPDATE OF i SKIP LOCKED
  LOOP
   BEGIN
    UPDATE public.incidents
       SET reminder_count   = reminder_count + 1,
           last_reminder_at = now()
     WHERE id = rem.id
       AND first_action_at IS NULL
       AND reminder_count = rem.reminder_count;
    CONTINUE WHEN NOT FOUND;

    v_n       := rem.reminder_count + 1;
    v_minutes := floor(extract(epoch FROM (now() - rem.created_at)) / 60)::integer;

    INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
    SELECT p.id,
           'STILL UNATTENDED - ' || v_minutes || ' min',
           rem.category || ' in ' || rem.barangay_name || ' still has NO response after '
             || v_minutes || ' min. Please respond now or call for help.',
           'escalation', rem.id, FALSE,
           jsonb_build_object('kind', 'unanswered', 'level', 3, 'minutes', v_minutes,
                              'reminder', v_n, 'after_hours', NOT v_working)
      FROM public.profiles p
     WHERE p.is_locked = FALSE
       AND ((p.role = 'admin' AND p.barangay_id = rem.barangay_id) OR p.role = 'superadmin');

    IF rem.reporter_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = rem.reporter_id) THEN
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
      VALUES (
        rem.reporter_id,
        'Still waiting / Naghihintay pa rin',
        'We know you are still waiting, and we are sorry. Nobody from the barangay has answered yet. Please call the emergency numbers in the app.'
          || E'\n' || 'Alam naming naghihintay pa rin kayo, at humihingi kami ng paumanhin. Wala pang sumasagot mula sa barangay. Mangyaring tumawag sa mga emergency number sa app.',
        'escalation_resident', rem.id, FALSE,
        jsonb_build_object('level', 3, 'reminder', v_n)
      );
    END IF;

    v_total := v_total + 1;
   EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'reminder failed for incident %: %', rem.id, SQLERRM;
   END;
  END LOOP;

  RETURN v_total;
END $$;

REVOKE ALL ON FUNCTION public.escalate_unanswered_reports() FROM PUBLIC, anon, authenticated;


-- ── 2f. "Good news": the first official action tells the resident ───────────
-- Also fires when the first action comes AFTER tier 3, so the resident always
-- learns that help is on the way.
CREATE OR REPLACE FUNCTION public.notify_resident_of_first_action()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name text;
  v_role text;
  v_label text;
BEGIN
  IF OLD.first_action_at IS NULL AND NEW.first_action_at IS NOT NULL
     AND NEW.reporter_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.reporter_id)
  THEN
    SELECT a.name, a.role_label INTO v_name, v_role
      FROM public.actor_label(COALESCE(NEW.first_action_by, NEW.assigned_to)) a;

    v_label := CASE v_role
                 WHEN 'captain'   THEN 'Barangay Captain'
                 WHEN 'secretary' THEN 'Barangay Secretary'
                 WHEN 'tanod'     THEN 'Tanod'
                 WHEN 'staff'     THEN 'Barangay Staff'
                 ELSE 'Barangay Official'
               END;

    -- A message that fails to send must never stop the official's own action
    -- (changing the status) from going through.
    BEGIN
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
      VALUES (
        NEW.reporter_id,
        'Help is on the way / May tumutugon na',
        'Good news! ' || v_label || ' ' || COALESCE(v_name, '') || ' is now responding to your report.'
          || E'\n' || 'Magandang balita po! May tumutugon na sa inyong report: '
          || v_label || ' ' || COALESCE(v_name, '') || '.',
        'responder_update', NEW.id, FALSE,
        jsonb_build_object('role', v_role, 'name', v_name)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'good-news notification failed for incident %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $$;

-- The officials who were alerted about an unanswered report are told when someone
-- takes it, so they stop worrying about it and nobody goes to the same scene.
-- Only for reports that were actually escalated (an ordinary report that is
-- answered within five minutes sends nobody anything).
CREATE OR REPLACE FUNCTION public.notify_alerted_officials_of_first_action()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := COALESCE(NEW.first_action_by, NEW.assigned_to);
  v_name  text;
  v_role  text;
  v_label text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.report_escalation_events WHERE report_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  SELECT a.name, a.role_label INTO v_name, v_role FROM public.actor_label(v_actor) a;
  v_label := CASE v_role
               WHEN 'captain'   THEN 'Barangay Captain'
               WHEN 'secretary' THEN 'Barangay Secretary'
               WHEN 'tanod'     THEN 'Tanod'
               WHEN 'staff'     THEN 'Barangay Staff'
               WHEN 'superadmin' THEN 'City Administrator'
               ELSE 'An official'
             END;

  BEGIN
    INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read, data)
    SELECT x.u,
           'Report taken',
           v_label || ' ' || COALESCE(v_name, '') || ' is now responding to the '
             || NEW.category || ' report. No further action needed unless asked.',
           'responder_taken', NEW.id, FALSE,
           jsonb_build_object('role', v_role, 'name', v_name)
      FROM (SELECT DISTINCT unnest(notified_user_ids) AS u
              FROM public.report_escalation_events
             WHERE report_id = NEW.id) x
     WHERE x.u IS DISTINCT FROM v_actor;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'report-taken notice failed for incident %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_officials_taken ON public.incidents;
CREATE TRIGGER trg_notify_officials_taken
  AFTER UPDATE ON public.incidents
  FOR EACH ROW WHEN (OLD.first_action_at IS NULL AND NEW.first_action_at IS NOT NULL)
  EXECUTE FUNCTION public.notify_alerted_officials_of_first_action();

DROP TRIGGER IF EXISTS trg_notify_first_action ON public.incidents;
-- Not "AFTER UPDATE OF first_action_at": Postgres only counts columns named in the
-- UPDATE's own SET list, and first_action_at is filled in by another trigger.
CREATE TRIGGER trg_notify_first_action
  AFTER UPDATE ON public.incidents
  FOR EACH ROW WHEN (OLD.first_action_at IS NULL AND NEW.first_action_at IS NOT NULL)
  EXECUTE FUNCTION public.notify_resident_of_first_action();


-- ── 2g. The hour-based job now watches HANDLED reports only ─────────────────
-- (Waiting reports belong to the minute-based job above.)
CREATE OR REPLACE FUNCTION public.escalation_level_for(
  p_status     text,
  p_created_at timestamptz,
  p_now        timestamptz DEFAULT now()
)
RETURNS smallint
LANGUAGE sql IMMUTABLE AS $$
  SELECT (
    CASE
      WHEN p_status IN ('resolved', 'closed', 'flagged') THEN 0
      WHEN t.hours >= 72 THEN 3
      WHEN t.hours >= 48 THEN 2
      WHEN t.hours >= 24 THEN 1
      ELSE 0
    END
  )::smallint
  FROM (SELECT extract(epoch FROM (p_now - p_created_at)) / 3600.0 AS hours) t;
$$;

-- Same body as migration_2026_10_15_escalation.sql, with one new filter: only
-- reports someone has already taken. 'pending' is excluded (minute job).
CREATE OR REPLACE FUNCTION public.escalate_overdue_incidents()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    SELECT i.id, i.barangay_id, i.category, i.status, i.assigned_to, i.created_at,
           COALESCE(b.name, 'a barangay') AS barangay_name,
           COALESCE((SELECT max(e.level) FROM public.incident_escalations e
                      WHERE e.incident_id = i.id), 0) AS done_level
      FROM public.incidents i
      LEFT JOIN public.barangays b ON b.id = i.barangay_id
     WHERE i.status IN ('verified', 'assigned', 'in_progress', 'responding', 'on_scene')
       AND i.created_at >= now() - interval '14 days'
  LOOP
    v_level := public.escalation_level_for(inc.status, inc.created_at);
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
            p.id = inc.assigned_to
         OR (p.role = 'admin' AND p.barangay_id = inc.barangay_id
             AND p.position IN ('secretary', 'captain')
             AND (v_level >= 2 OR inc.assigned_to IS NULL))
         OR (p.role = 'superadmin' AND v_level >= 3)
       );
    GET DIAGNOSTICS v_sent = ROW_COUNT;

    IF v_sent = 0 THEN
      INSERT INTO public.notifications (user_id, title, body, type, incident_id, is_read)
      SELECT p.id, v_title, v_body, 'escalation', inc.id, FALSE
        FROM public.profiles p
       WHERE p.is_locked = FALSE AND p.role = 'admin' AND p.barangay_id = inc.barangay_id;
      GET DIAGNOSTICS v_sent = ROW_COUNT;
    END IF;

    INSERT INTO public.incident_escalations (incident_id, level, recipients)
    VALUES (inc.id, v_level, v_sent)
    ON CONFLICT (incident_id, level) DO NOTHING;

    v_total := v_total + 1;
  END LOOP;

  RETURN v_total;
END $$;

REVOKE ALL ON FUNCTION public.escalate_overdue_incidents() FROM PUBLIC, anon, authenticated;


-- ── 2h. Schedule: every 30 seconds (every minute if this pg_cron is older) ──
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule(jobid)
  FROM cron.job
 WHERE jobname = 'escalate-unanswered-reports';

DO $$
BEGIN
  BEGIN
    PERFORM cron.schedule('escalate-unanswered-reports', '30 seconds',
                          'SELECT public.escalate_unanswered_reports();');
  EXCEPTION WHEN OTHERS THEN
    PERFORM cron.schedule('escalate-unanswered-reports', '* * * * *',
                          'SELECT public.escalate_unanswered_reports();');
  END;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 3 — TUTORIAL USAGE LOG
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.tutorial_logs (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  opened_at    timestamptz NOT NULL DEFAULT now(),
  completed    boolean     NOT NULL DEFAULT FALSE,
  steps_viewed integer     NOT NULL DEFAULT 0,
  source       text        NOT NULL DEFAULT 'button' CHECK (source IN ('auto', 'button', 'form_help')),
  practice     boolean     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_tutorial_logs_user ON public.tutorial_logs (user_id, opened_at DESC);

ALTER TABLE public.tutorial_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users log their own tutorial use" ON public.tutorial_logs;
CREATE POLICY "Users log their own tutorial use"
  ON public.tutorial_logs FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users update their own tutorial rows" ON public.tutorial_logs;
CREATE POLICY "Users update their own tutorial rows"
  ON public.tutorial_logs FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Read tutorial log" ON public.tutorial_logs;
CREATE POLICY "Read tutorial log"
  ON public.tutorial_logs FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR get_user_role() = 'superadmin');

REVOKE DELETE, TRUNCATE ON public.tutorial_logs FROM PUBLIC, anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- THE METRICS VIEW  (created last: it reads everything above)
-- ════════════════════════════════════════════════════════════════════════════
-- One row per report. Durations are whole SECONDS (the app and the export turn
-- them into minutes:seconds), NULL when a step has not happened - or happened
-- before this feature existed. Missing values stay blank; nothing is estimated.
--
-- What is deliberately NOT here: latitude, longitude, address, landmark, phone,
-- email, ID, photos. The export cannot leak what the view does not contain.
--
-- security_invoker: the view runs with the CALLER's permissions, so the existing
-- row-level rules apply - a barangay admin gets their own barangay, the
-- superadmin gets all, a resident gets nothing.
CREATE OR REPLACE VIEW public.report_response_metrics
WITH (security_invoker = true) AS
SELECT
  i.id                                   AS report_id,
  COALESCE(rp.full_name, ns.full_name)   AS resident_name,
  i.barangay_id,
  b.name                                 AS barangay_name,
  i.category,
  i.severity_level                       AS severity,
  i.status                               AS final_status,
  i.created_at                           AS submitted_at,
  i.first_seen_at,
  i.first_action_at,
  i.verified_at                          AS acknowledged_at,
  i.assigned_at,
  i.responding_at                        AS dispatched_at,
  i.on_scene_at,
  i.resolved_at,
  i.closed_at,
  i.escalation_level                     AS escalation_level_reached,
  ev.level_1_at,
  ev.level_2_at,
  ev.level_3_at,
  COALESCE(ap.full_name, fp.full_name)   AS responder_name,
  COALESCE(ap.position, ap.role, fp.position, fp.role) AS responder_role,
  extract(epoch FROM (i.first_seen_at   - i.created_at))::bigint   AS secs_to_first_seen,
  extract(epoch FROM (i.first_action_at - i.created_at))::bigint   AS secs_to_first_response,
  extract(epoch FROM (i.responding_at   - i.created_at))::bigint   AS secs_to_dispatch,
  extract(epoch FROM (i.on_scene_at     - i.responding_at))::bigint AS secs_travel,
  extract(epoch FROM (i.resolved_at     - i.created_at))::bigint   AS secs_to_resolve,
  extract(epoch FROM (i.closed_at       - i.created_at))::bigint   AS secs_total_open,
  (i.escalation_level > 0)               AS was_escalated,
  CASE WHEN i.first_action_at IS NULL THEN NULL
       ELSE i.first_action_at - i.created_at <= interval '5 minutes'  END AS answered_within_5,
  CASE WHEN i.first_action_at IS NULL THEN NULL
       ELSE i.first_action_at - i.created_at <= interval '10 minutes' END AS answered_within_10,
  CASE WHEN i.first_action_at IS NULL THEN NULL
       ELSE i.first_action_at - i.created_at <= interval '15 minutes' END AS answered_within_15
FROM public.incidents i
LEFT JOIN public.barangays b                ON b.id  = i.barangay_id
LEFT JOIN public.profiles rp                ON rp.id = i.reporter_id
LEFT JOIN public.non_resident_sessions ns   ON ns.id = i.reported_by_session_id
LEFT JOIN public.profiles ap                ON ap.id = i.assigned_to
LEFT JOIN public.profiles fp                ON fp.id = i.first_action_by
LEFT JOIN LATERAL (
  SELECT
    max(e.triggered_at) FILTER (WHERE e.level = 1) AS level_1_at,
    max(e.triggered_at) FILTER (WHERE e.level = 2) AS level_2_at,
    max(e.triggered_at) FILTER (WHERE e.level = 3) AS level_3_at
  FROM public.report_escalation_events e
  WHERE e.report_id = i.id
) ev ON TRUE;

REVOKE ALL ON public.report_response_metrics FROM PUBLIC, anon;
GRANT SELECT ON public.report_response_metrics TO authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- VERIFY (run these yourself afterwards)
-- ════════════════════════════════════════════════════════════════════════════
--  1. Both jobs scheduled:
--       SELECT jobname, schedule, active FROM cron.job;
--  2. After a minute, the job is running:
--       SELECT status, return_message, start_time FROM cron.job_run_details
--        ORDER BY start_time DESC LIMIT 5;
--  3. Settings (change step_seconds for a demo, then set it back to 300):
--       SELECT * FROM public.escalation_settings;
--  4. See what a test report did:
--       SELECT level, triggered_at, array_length(notified_user_ids, 1) AS people
--         FROM public.report_escalation_events ORDER BY triggered_at DESC;
--       SELECT * FROM public.report_status_logs ORDER BY changed_at DESC LIMIT 10;
