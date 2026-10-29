-- ============================================================================
-- Migration: report integrity signals (§5)
-- Date: 2026-08-16
-- ============================================================================
--
-- PURPOSE
--   Record whether a report was filed over a VPN, and whether the device
--   reported a mock (spoofed) GPS position.
--
-- WHY BOTH, AND WHY MOCK LOCATION MATTERS MORE
--   A VPN changes the IP address, not the GPS fix. Every location this app
--   cares about — the geofence, the incident pin, responder tracking — comes
--   from GPS. So the signal that actually threatens report integrity is a
--   mock-location app, which Android exposes directly and geolocator surfaces
--   as `Position.isMocked`. VPN is recorded because §5 asks for it and it is
--   free to collect, but it is the weaker signal of the two.
--
-- WHY FLAG AND NOT BLOCK
--   Deliberately advisory. Blocking a report because someone runs a VPN would
--   mean refusing an emergency from a person whose phone happens to have one
--   switched on — indefensible for a safety app, and it would push a real
--   emergency off the system entirely. The Secretary already verifies every
--   report before anyone is dispatched (the six-stage flow), so the right
--   place for this is a warning on their review screen, not a locked door.
--
-- SAFETY
--   Additive only. Both columns default false, so existing rows are unchanged
--   and read as "no concern raised" rather than "checked and clean" — which is
--   accurate: reports filed before today were never checked.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS reported_via_vpn BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS location_mocked BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.incidents.reported_via_vpn IS
  'Advisory only. Device reported an active VPN transport when filing. Never blocks a report.';

COMMENT ON COLUMN public.incidents.location_mocked IS
  'Advisory only. Device reported the GPS fix as mocked (Position.isMocked). The stronger of the two integrity signals.';

-- Officials filter for flagged reports when reviewing; without this the check
-- scans the whole table. Partial index because the overwhelming majority of
-- rows are false and are never searched for.
CREATE INDEX IF NOT EXISTS idx_incidents_integrity_flagged
  ON public.incidents (barangay_id)
  WHERE reported_via_vpn OR location_mocked;

COMMIT;


-- ── Verify ─────────────────────────────────────────────────────────────────
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'incidents'
  AND column_name IN ('reported_via_vpn', 'location_mocked');
