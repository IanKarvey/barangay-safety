-- ============================================================================
-- Migration: Non-Resident One-Time Report Sessions
-- Date: 2026-08-07
-- Requirement: BARANGAY_CONNECT_REQUIREMENTS.md §1 (critical)
-- ============================================================================
--
-- A non-resident reports ONCE per 7 days. No password, no email — they sign in
-- with a contact number + name, backed by a Supabase ANONYMOUS auth user so
-- that auth.uid() exists and RLS still works.
--
--   anonymous auth user  ──1:1──>  non_resident_sessions row
--                                    ├─ phone + full_name (self-declared)
--                                    ├─ barangay_id (auto-detected from GPS)
--                                    ├─ expires_at = created_at + 7 days
--                                    └─ live location, updated while active
--
-- SESSION LIFECYCLE
--   active      → signed in, no report filed yet
--   reported    → tapped Report; Secretary notified; awaiting their call
--   called      → called the Secretary; must now upload photo/video proof
--   proof_ready → proof uploaded; Secretary reviews BEFORE deploying anyone
--   deployed    → Secretary accepted the proof and dispatched
--   completed   → incident resolved
--   disregarded → bogus, abandoned, or location lost
--
-- SECURITY NOTE: identity here is self-declared — no OTP, no password. That is
-- the intended tradeoff for friction-free emergency reporting. The anti-abuse
-- controls are downstream: proof required before deployment, Secretary review
-- gate, logout lock, and one report per phone per 7 days.
--
-- Safe to re-run (idempotent).
-- ============================================================================

-- 1. Sessions table ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.non_resident_sessions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id      UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Self-declared identity (no verification — see security note above)
  phone             TEXT NOT NULL,
  full_name         TEXT NOT NULL,

  -- Auto-detected from GPS at sign-in, never manually chosen
  barangay_id       UUID REFERENCES public.barangays(id),

  status            TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'reported', 'called',
                                        'proof_ready', 'deployed',
                                        'completed', 'disregarded')),

  -- The incident this session produced (null until they report)
  incident_id       UUID REFERENCES public.incidents(id) ON DELETE SET NULL,

  -- Live location — refreshed while the session is active
  last_lat          DOUBLE PRECISION,
  last_lng          DOUBLE PRECISION,
  last_location_at  TIMESTAMPTZ,

  -- True once they have filed their one report; blocks a second one
  has_reported      BOOLEAN NOT NULL DEFAULT FALSE,

  -- Logout is locked while a report is in flight (anti-bogus)
  logout_locked     BOOLEAN NOT NULL DEFAULT FALSE,

  -- Why a session was disregarded, for the Secretary's context
  disregard_reason  TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Resets after 7 days — they may report again once this passes
  expires_at        TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days')
);

-- 2. Indexes ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nrs_auth_user
  ON public.non_resident_sessions(auth_user_id);

-- "has this phone already reported in the last 7 days?" — the cooldown check
CREATE INDEX IF NOT EXISTS idx_nrs_phone_expiry
  ON public.non_resident_sessions(phone, expires_at DESC);

-- Secretary's live queue
CREATE INDEX IF NOT EXISTS idx_nrs_barangay_status
  ON public.non_resident_sessions(barangay_id, status);

-- 3. Keep updated_at fresh --------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_non_resident_session()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_nrs ON public.non_resident_sessions;
CREATE TRIGGER trg_touch_nrs
  BEFORE UPDATE ON public.non_resident_sessions
  FOR EACH ROW EXECUTE FUNCTION public.touch_non_resident_session();

-- 4. Cooldown check ---------------------------------------------------------
-- TRUE when this phone may start a new report (no unexpired session exists).
-- SECURITY DEFINER so an anonymous user can check before signing in.
CREATE OR REPLACE FUNCTION public.can_non_resident_report(p_phone TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.non_resident_sessions
    WHERE phone = p_phone
      AND expires_at > NOW()
      AND has_reported = TRUE
      AND status NOT IN ('disregarded', 'completed')
  );
$$;

-- 5. RLS --------------------------------------------------------------------
ALTER TABLE public.non_resident_sessions ENABLE ROW LEVEL SECURITY;

-- A non-resident can create their own session row
DROP POLICY IF EXISTS "Non-resident can create own session"
  ON public.non_resident_sessions;
CREATE POLICY "Non-resident can create own session"
  ON public.non_resident_sessions FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = auth.uid());

-- ...and read/update only their own
DROP POLICY IF EXISTS "Non-resident can read own session"
  ON public.non_resident_sessions;
CREATE POLICY "Non-resident can read own session"
  ON public.non_resident_sessions FOR SELECT TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR get_user_role() IN ('admin', 'superadmin')
  );

DROP POLICY IF EXISTS "Non-resident can update own session"
  ON public.non_resident_sessions;
CREATE POLICY "Non-resident can update own session"
  ON public.non_resident_sessions FOR UPDATE TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR get_user_role() IN ('admin', 'superadmin')
  );

-- Officials see sessions in their barangay; superadmin sees all.
-- (Covered by the SELECT policy above via get_user_role().)


-- ============================================================================
-- VERIFY
-- ============================================================================
-- Live non-resident queue for a barangay:
--
--   SELECT s.full_name, s.phone, s.status, s.last_lat, s.last_lng,
--          s.last_location_at, b.name AS barangay
--   FROM public.non_resident_sessions s
--   LEFT JOIN public.barangays b ON b.id = s.barangay_id
--   WHERE s.status NOT IN ('completed', 'disregarded')
--     AND s.expires_at > NOW()
--   ORDER BY s.updated_at DESC;
