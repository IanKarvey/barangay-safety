-- ============================================================================
-- BATCH MIGRATION — run this whole file once in the Supabase SQL Editor
-- Date: 2026-08-09
-- ============================================================================
--
-- Bundles the three schema changes needed to unblock:
--   PART 1 — Official live location broadcast   (§1: "see them coming")
--   PART 2 — Six-stage incident tracking        (§15 Shopee-style tracking)
--   PART 3 — Date of birth for age analytics    (§10: 45+ user count)
--
-- ALL THREE ARE ADDITIVE. No column is dropped, no data is deleted, no
-- existing value becomes invalid. Every existing incident and profile keeps
-- working exactly as before.
--
-- Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- PART 1 — Official live location broadcast
-- ════════════════════════════════════════════════════════════════════════════
-- Lets a reporter watch help approach instead of staring at a static pin.
--
-- PRIVACY: opt-in and session-scoped. `is_sharing_location` gates everything;
-- when false, coordinates are neither written nor served. An official is not
-- tracked merely by being logged in.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_lat             DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_lng             DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_location_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_sharing_location  BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_profiles_sharing_location
  ON public.profiles(barangay_id, is_sharing_location)
  WHERE is_sharing_location = TRUE;

-- A non-resident is an anonymous user with no profiles row, so the existing
-- profile policies deny them everything. Rather than widen those policies and
-- risk exposing officials' personal data, expose ONLY what a reporter needs.
-- No email, no phone, no ID photo.
CREATE OR REPLACE VIEW public.responder_locations AS
  SELECT
    p.id,
    p.full_name,
    p.position,
    p.barangay_id,
    p.last_lat,
    p.last_lng,
    p.last_location_at
  FROM public.profiles p
  WHERE p.is_sharing_location = TRUE
    AND p.last_lat IS NOT NULL
    AND p.last_lng IS NOT NULL
    AND p.is_locked = FALSE;

GRANT SELECT ON public.responder_locations TO authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 2 — Six-stage incident tracking (§15)
-- ════════════════════════════════════════════════════════════════════════════
-- Target flow:
--   Report Submitted → Secretary Verified → Official Assigned
--     → Responders En Route → On Scene → Resolved → Closed
--
-- The OLD values are deliberately kept. 'in_progress' in particular still
-- exists so every incident already in the database stays valid and the app
-- keeps working during the transition — dropping it would strand live rows.

ALTER TABLE public.incidents
  DROP CONSTRAINT IF EXISTS incidents_status_check;

ALTER TABLE public.incidents
  ADD CONSTRAINT incidents_status_check
  CHECK (status IN (
    -- legacy, still valid
    'pending', 'in_progress', 'resolved', 'flagged',
    -- new six-stage flow
    'verified', 'assigned', 'responding', 'on_scene', 'closed'
  ));

-- Timestamps per stage, so response times can be measured properly rather
-- than inferred from a single updated_at.
ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS verified_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assigned_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS responding_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS on_scene_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_at     TIMESTAMPTZ;

-- Stamp the matching timestamp automatically on each stage transition.
CREATE OR REPLACE FUNCTION public.stamp_incident_stage()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'verified'   THEN NEW.verified_at   := COALESCE(NEW.verified_at, NOW());
      WHEN 'assigned'   THEN NEW.assigned_at   := COALESCE(NEW.assigned_at, NOW());
      WHEN 'responding' THEN NEW.responding_at := COALESCE(NEW.responding_at, NOW());
      WHEN 'on_scene'   THEN NEW.on_scene_at   := COALESCE(NEW.on_scene_at, NOW());
      WHEN 'closed'     THEN NEW.closed_at     := COALESCE(NEW.closed_at, NOW());
      ELSE NULL;
    END CASE;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_incident_stage ON public.incidents;
CREATE TRIGGER trg_stamp_incident_stage
  BEFORE UPDATE ON public.incidents
  FOR EACH ROW EXECUTE FUNCTION public.stamp_incident_stage();


-- ════════════════════════════════════════════════════════════════════════════
-- PART 3 — Date of birth, for age analytics (§10)
-- ════════════════════════════════════════════════════════════════════════════
-- Stores date of birth rather than an age number, so it never goes stale.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;

-- Rejects impossible dates (future, or implausibly old) without blocking NULL,
-- since every existing profile has no DOB yet.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_dob_sane;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_dob_sane
  CHECK (
    date_of_birth IS NULL
    OR (date_of_birth > DATE '1900-01-01' AND date_of_birth <= CURRENT_DATE)
  );

CREATE INDEX IF NOT EXISTS idx_profiles_dob
  ON public.profiles(date_of_birth)
  WHERE date_of_birth IS NOT NULL;

-- Age-bracket counts for the dashboard. SECURITY DEFINER so officials can read
-- aggregate demographics without needing SELECT on every profile row.
CREATE OR REPLACE FUNCTION public.get_age_demographics(p_barangay_id UUID DEFAULT NULL)
RETURNS TABLE (
  bracket    TEXT,
  user_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE
      WHEN date_of_birth IS NULL THEN 'unknown'
      WHEN AGE(date_of_birth) < INTERVAL '18 years' THEN 'under_18'
      WHEN AGE(date_of_birth) < INTERVAL '45 years' THEN '18_to_44'
      ELSE '45_and_over'
    END AS bracket,
    COUNT(*) AS user_count
  FROM public.profiles
  WHERE (p_barangay_id IS NULL OR barangay_id = p_barangay_id)
  GROUP BY 1
  ORDER BY 1;
$$;

-- Headline counts for the dashboard: total users, and barangay hall personnel.
CREATE OR REPLACE FUNCTION public.get_user_stats(p_barangay_id UUID DEFAULT NULL)
RETURNS TABLE (
  total_users     BIGINT,
  residents       BIGINT,
  non_residents   BIGINT,
  personnel       BIGINT,
  age_45_plus     BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(*)                                                        AS total_users,
    COUNT(*) FILTER (WHERE role = 'resident')                       AS residents,
    COUNT(*) FILTER (WHERE role = 'non_resident')                   AS non_residents,
    COUNT(*) FILTER (WHERE position IS NOT NULL)                    AS personnel,
    COUNT(*) FILTER (
      WHERE date_of_birth IS NOT NULL
        AND AGE(date_of_birth) >= INTERVAL '45 years'
    )                                                               AS age_45_plus
  FROM public.profiles
  WHERE (p_barangay_id IS NULL OR barangay_id = p_barangay_id);
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- PART 4 — Non-resident reports become real incident records
-- ════════════════════════════════════════════════════════════════════════════
-- "Every report needs a record." Non-resident emergencies lived only in
-- non_resident_sessions, so they were invisible to analytics, PDF export, the
-- incident map and All Reports — the barangay had no auditable trail of them.
--
-- Blocker: incidents.reporter_id is NOT NULL REFERENCES profiles(id), and an
-- anonymous non-resident deliberately has no profiles row. So reporter_id is
-- relaxed to nullable and a session reference added alongside it.
--
--   resident report      → reporter_id set,  reported_by_session_id NULL
--   non-resident report  → reporter_id NULL, reported_by_session_id set
--
-- Relaxing NOT NULL cannot invalidate existing rows — every current incident
-- already has a reporter_id.

ALTER TABLE public.incidents
  ALTER COLUMN reporter_id DROP NOT NULL;

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS reported_by_session_id UUID
    REFERENCES public.non_resident_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_incidents_session
  ON public.incidents(reported_by_session_id)
  WHERE reported_by_session_id IS NOT NULL;

-- Guard: an incident must have exactly one origin.
ALTER TABLE public.incidents
  DROP CONSTRAINT IF EXISTS incidents_has_an_origin;

ALTER TABLE public.incidents
  ADD CONSTRAINT incidents_has_an_origin
  CHECK (reporter_id IS NOT NULL OR reported_by_session_id IS NOT NULL);


-- Create the incident when a non-resident reports, and keep it in step with
-- the session afterwards. SECURITY DEFINER because the anonymous user has no
-- rights to insert into incidents directly.
CREATE OR REPLACE FUNCTION public.sync_non_resident_incident()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_incident_id UUID;
BEGIN
  -- On the transition into 'reported', create the incident record.
  IF NEW.status = 'reported'
     AND OLD.status IS DISTINCT FROM 'reported'
     AND NEW.incident_id IS NULL THEN

    INSERT INTO public.incidents (
      reporter_id, reported_by_session_id, barangay_id,
      category, description, severity_level, status,
      latitude, longitude
    )
    VALUES (
      NULL,
      NEW.id,
      NEW.barangay_id,
      'Emergency (Non-Resident)',
      COALESCE(NEW.full_name, 'A visitor')
        || ' reported an emergency via the non-resident flow. Contact: '
        || COALESCE(NEW.phone, 'unknown'),
      1,          -- non-resident reports are call-based emergencies
      'pending',
      COALESCE(NEW.last_lat, 0),
      COALESCE(NEW.last_lng, 0)
    )
    RETURNING id INTO v_incident_id;

    NEW.incident_id := v_incident_id;
    RETURN NEW;
  END IF;

  -- Mirror later session outcomes onto the incident so exports and the
  -- resolution rate stay truthful.
  IF NEW.incident_id IS NOT NULL
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE public.incidents
    SET status = CASE NEW.status
                   WHEN 'deployed'    THEN 'responding'
                   WHEN 'completed'   THEN 'resolved'
                   WHEN 'disregarded' THEN 'flagged'
                   ELSE status
                 END,
        resolved_at = CASE WHEN NEW.status = 'completed'
                           THEN NOW() ELSE resolved_at END,
        updated_at = NOW()
    WHERE id = NEW.incident_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_non_resident_incident
  ON public.non_resident_sessions;

-- BEFORE UPDATE so the assignment to NEW.incident_id is persisted.
CREATE TRIGGER trg_sync_non_resident_incident
  BEFORE UPDATE ON public.non_resident_sessions
  FOR EACH ROW EXECUTE FUNCTION public.sync_non_resident_incident();


-- Officials must be able to read incidents that have no reporter_id.
DROP POLICY IF EXISTS "Officials can view non-resident incidents"
  ON public.incidents;
CREATE POLICY "Officials can view non-resident incidents"
  ON public.incidents FOR SELECT TO authenticated
  USING (
    reported_by_session_id IS NOT NULL
    AND get_user_role() IN ('admin', 'superadmin')
  );


-- ════════════════════════════════════════════════════════════════════════════
-- PART 5 — Make sure realtime is publishing the tables the app subscribes to
-- ════════════════════════════════════════════════════════════════════════════
-- The reporter's app watches its own session row so official decisions
-- (deployed / resolved / disregarded) reach it live. If the table isn't in the
-- `supabase_realtime` publication that subscription silently receives nothing
-- — no error, just a screen that never updates. This is the prime suspect for
-- the status popup not having been observed working.
--
-- Wrapped in exception handlers because ALTER PUBLICATION errors if the table
-- is already a member, and that is a perfectly fine state to be in.

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.non_resident_sessions;
EXCEPTION
  WHEN duplicate_object THEN NULL;  -- already published
  WHEN undefined_object THEN NULL;  -- publication missing on this project
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.incidents;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;


-- ============================================================================
-- VERIFY — run after the migration
-- ============================================================================
-- Confirm realtime publishes what the app subscribes to:
--   SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime' ORDER BY tablename;
--
-- Non-resident reports now appear as incidents:
--   SELECT i.id, i.category, i.status, i.severity_level, s.full_name, s.phone
--   FROM public.incidents i
--   JOIN public.non_resident_sessions s ON s.id = i.reported_by_session_id
--   ORDER BY i.created_at DESC;

--   SELECT * FROM public.get_user_stats();
--   SELECT * FROM public.get_age_demographics();
--   SELECT * FROM public.responder_locations;
--
--   -- confirm the new statuses are accepted
--   SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint WHERE conname = 'incidents_status_check';
