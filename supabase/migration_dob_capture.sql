-- ============================================================================
-- Migration: capture date_of_birth at signup (§10 analytics)
-- Date: 2026-08-11
-- ============================================================================
--
-- PROBLEM
--   `profiles.date_of_birth`, `get_age_demographics()` and `get_user_stats()`
--   were all added by migration_batch_2026_08_09 (PART 3) and work — but
--   nothing ever writes a DOB, so `age_45_plus` reads 0 for every barangay and
--   the demographic is permanently useless.
--
--   The app now collects a DOB on the registration form and passes it in the
--   auth metadata. But the profiles row is created by the existing
--   `handle_new_user()` trigger, which predates the column and does not copy
--   it across.
--
-- FIX
--   A separate BEFORE INSERT trigger on `profiles` that pulls date_of_birth out
--   of `auth.users.raw_user_meta_data`.
--
--   Deliberately NOT a rewrite of `handle_new_user()`. That function was
--   created through the dashboard and its body is not in this repo — rewriting
--   it from a guess risks breaking registration entirely for a cosmetic
--   statistic. This trigger is additive and composes with whatever
--   handle_new_user() currently does.
--
--   It only fills a NULL, so it can never overwrite a value set deliberately,
--   and it is a no-op for anonymous users (they get no profiles row at all —
--   see migration_anon_user_trigger_fix.sql).
--
-- SAFETY
--   Wrapped in a transaction. Additive only: no column dropped, no existing
--   function modified, no data rewritten. Existing profiles keep
--   date_of_birth = NULL and are reported under the 'unknown' bracket, which
--   get_age_demographics() already handles.
--
-- Safe to re-run (idempotent).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.copy_dob_from_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fill a gap; never clobber an explicit value.
  IF NEW.date_of_birth IS NULL THEN
    SELECT NULLIF(u.raw_user_meta_data ->> 'date_of_birth', '')::DATE
      INTO NEW.date_of_birth
    FROM auth.users u
    WHERE u.id = NEW.id;
  END IF;

  RETURN NEW;
EXCEPTION
  -- A malformed date in metadata must never block account creation. Losing a
  -- demographic data point is trivial; failing a registration is not.
  WHEN others THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_copy_dob ON public.profiles;

CREATE TRIGGER profiles_copy_dob
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.copy_dob_from_metadata();

COMMIT;


-- ── Verify ─────────────────────────────────────────────────────────────────
-- Expect one row: profiles_copy_dob / INSERT.
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'profiles'
  AND trigger_name = 'profiles_copy_dob';
