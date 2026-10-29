-- ============================================================================
-- Migration: Let anonymous users sign in
-- Date: 2026-08-07
-- Requirement: BARANGAY_CONNECT_REQUIREMENTS.md §1 (non-resident flow)
-- ============================================================================
--
-- PROBLEM
--   signInAnonymously() failed with:
--     500 "Database error creating anonymous user"
--
--   The `on_auth_user_created` trigger fires on EVERY auth.users insert and
--   calls handle_new_user(), which inserts a profiles row. profiles requires
--   email, full_name and phone to be NOT NULL — an anonymous user has none of
--   them, so the insert violates the constraint, the trigger errors, and the
--   entire signup transaction rolls back.
--
-- FIX
--   Add a WHEN clause so the trigger skips anonymous users. handle_new_user()
--   itself is NOT modified — resident and non-resident registration keep
--   behaving exactly as before.
--
--   Anonymous users intentionally have no profiles row. Their identity lives
--   in non_resident_sessions instead, and get_user_role() returning NULL for
--   them is what keeps existing RLS policies denying them access.
--
-- SAFETY
--   Wrapped in a transaction. Postgres DDL is transactional, so if the CREATE
--   fails (e.g. this Supabase version has no auth.users.is_anonymous column),
--   the DROP rolls back too and the original trigger is left intact. It cannot
--   leave you with no trigger and broken registration.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (NEW.is_anonymous IS NOT TRUE)
  EXECUTE FUNCTION handle_new_user();

COMMIT;


-- ============================================================================
-- VERIFY — the definition should now contain the WHEN clause
-- ============================================================================
--   SELECT tgname, pg_get_triggerdef(oid)
--   FROM pg_trigger
--   WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal;
