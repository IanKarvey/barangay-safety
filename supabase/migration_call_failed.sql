-- ============================================================================
-- Migration: Record when a non-resident could not call the barangay
-- Date: 2026-08-09
-- Requirement: §1 — "what if they don't have any call credits?"
-- ============================================================================
--
-- PROBLEM
--   `_callBarangay()` caught a dialer failure, showed a snackbar, then fell
--   through to `setStatus('called')` regardless. A reporter with no load was
--   logged as having called the barangay when they never did — and Android
--   never reports whether a call actually connected, so the app cannot detect
--   this on its own.
--
--   The Secretary then sees "CALLED" and waits for a call that will not come,
--   at the exact moment waiting is most costly.
--
-- APPROACH
--   Record the failure explicitly instead of pretending success. Safe to do
--   because the barangay is already notified at the `reported` stage — the
--   call is confirmation, not the trigger.
--
-- Safe to re-run (idempotent).
-- ============================================================================

ALTER TABLE public.non_resident_sessions
  ADD COLUMN IF NOT EXISTS call_failed BOOLEAN NOT NULL DEFAULT FALSE;

-- Why they could not call, in their own words where offered
-- ('no_credits' | 'no_signal' | 'other' | NULL).
ALTER TABLE public.non_resident_sessions
  ADD COLUMN IF NOT EXISTS call_failed_reason TEXT;

ALTER TABLE public.non_resident_sessions
  DROP CONSTRAINT IF EXISTS non_resident_sessions_call_reason_check;

ALTER TABLE public.non_resident_sessions
  ADD CONSTRAINT non_resident_sessions_call_reason_check
  CHECK (
    call_failed_reason IS NULL
    OR call_failed_reason IN ('no_credits', 'no_signal', 'dialer_failed', 'other')
  );


-- ============================================================================
-- VERIFY
-- ============================================================================
--   SELECT full_name, phone, status, call_failed, call_failed_reason
--   FROM public.non_resident_sessions
--   ORDER BY created_at DESC;
