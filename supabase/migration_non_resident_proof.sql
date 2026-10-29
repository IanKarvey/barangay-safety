-- ============================================================================
-- Migration: Proof columns for non-resident sessions
-- Date: 2026-08-07
-- Requirement: BARANGAY_CONNECT_REQUIREMENTS.md §1 — "upload photo/video proof",
--              "secretary must view proof before deploying"
-- ============================================================================
--
-- Adds storage for the evidence a non-resident uploads after calling the
-- barangay. The file itself goes to the incident-photos bucket under
-- `non-resident/<sessionId>/`; these columns hold the resulting public URL.
--
-- Safe to re-run (idempotent).
-- ============================================================================

ALTER TABLE public.non_resident_sessions
  ADD COLUMN IF NOT EXISTS proof_url  TEXT,
  ADD COLUMN IF NOT EXISTS proof_type TEXT;

ALTER TABLE public.non_resident_sessions
  DROP CONSTRAINT IF EXISTS non_resident_sessions_proof_type_check;

ALTER TABLE public.non_resident_sessions
  ADD CONSTRAINT non_resident_sessions_proof_type_check
  CHECK (proof_type IS NULL OR proof_type IN ('photo', 'video'));
