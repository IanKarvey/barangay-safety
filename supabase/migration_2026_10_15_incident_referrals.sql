-- Incident referrals — a record that someone tried to report something beyond
-- the barangay (fire, accident, police matter...) and was sent to the right
-- agency instead of filing.
--
-- NOT an incident. Nothing here is assigned, tracked or expected to be
-- actioned; it exists so the barangay can see what happened inside its
-- boundaries even though it was never asked to respond. See
-- lib/utils/lgu_routing.dart and lib/services/referral_service.dart.
--
-- Safe to run more than once. The app works without this table (the log call
-- fails silently), so running it is what turns the record on.

CREATE TABLE IF NOT EXISTS public.incident_referrals (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  barangay_id uuid        REFERENCES public.barangays(id) ON DELETE SET NULL,
  category    text        NOT NULL,
  agency      text        NOT NULL,
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS incident_referrals_barangay_created_idx
  ON public.incident_referrals (barangay_id, created_at DESC);

ALTER TABLE public.incident_referrals ENABLE ROW LEVEL SECURITY;

-- ── Insert: a signed-in person records their own referral, and only theirs ──
DROP POLICY IF EXISTS "Users log their own referrals" ON public.incident_referrals;
CREATE POLICY "Users log their own referrals"
  ON public.incident_referrals FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- ── Read: officials see their own barangay's; the superadmin sees all ───────
-- A resident cannot read this table at all, including their own rows — the log
-- is for the barangay's monitoring, not a history screen.
-- Uses the existing SECURITY DEFINER helpers so this doesn't recurse into the
-- profiles policies.
DROP POLICY IF EXISTS "Officials read referrals" ON public.incident_referrals;
CREATE POLICY "Officials read referrals"
  ON public.incident_referrals FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'superadmin'
    OR (get_user_role() = 'admin' AND barangay_id = get_user_barangay())
  );

-- ── Verify ──────────────────────────────────────────────────────────────────
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'incident_referrals'
ORDER BY policyname;
