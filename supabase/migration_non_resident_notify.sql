-- ============================================================================
-- Migration: Notify barangay officials when a non-resident reports
-- Date: 2026-08-08
-- Requirement: BARANGAY_CONNECT_REQUIREMENTS.md §1 — "On tapping Report →
--              instant notification to Secretary"
-- ============================================================================
--
-- PROBLEM
--   A non-resident emergency only appeared in the queue if an official
--   happened to have that screen open. Nobody was actually alerted.
--
-- APPROACH
--   A trigger on non_resident_sessions fires when status becomes 'reported'
--   and inserts a row into `notifications` for every official in that
--   barangay. The app already streams that table and raises a local
--   notification (NotificationProvider.subscribe → LocalNotificationService),
--   so this alerts anyone with the app open or backgrounded.
--
--   Doing this in the database rather than the client means the alert cannot
--   be lost if the reporter's app crashes or loses signal right after
--   reporting — the exact moment it matters most.
--
--   For alerts when the app is FULLY CLOSED you also need the companion
--   Edge Function (supabase/functions/notify-non-resident-report), which
--   pushes via FCM. That requires deployment + a DB webhook; this trigger
--   works immediately with no setup.
--
-- Safe to re-run (idempotent).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_officials_of_non_resident_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER            -- bypasses RLS so it can write to other users' rows
SET search_path = public
AS $$
DECLARE
  official RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Only on the transition INTO 'reported' — not on later location updates,
  -- which fire this trigger roughly once per second.
  IF NEW.status IS DISTINCT FROM 'reported'
     OR OLD.status IS NOT DISTINCT FROM 'reported' THEN
    RETURN NEW;
  END IF;

  v_title := '🚨 Non-Resident Emergency Report';
  v_body  := COALESCE(NEW.full_name, 'A visitor')
             || ' reported an emergency and is sharing live location. '
             || 'Contact: ' || COALESCE(NEW.phone, 'unknown');

  -- Every official in the barangay the GPS resolved to. Secretary first so
  -- they are the first row inserted, but all officials are alerted — an
  -- emergency must not stall because one person is unavailable.
  FOR official IN
    SELECT id
    FROM public.profiles
    WHERE barangay_id = NEW.barangay_id
      AND role IN ('admin', 'superadmin')
      AND is_locked = FALSE
    ORDER BY (position = 'secretary') DESC NULLS LAST
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, is_read)
    VALUES (official.id, v_title, v_body, 'non_resident_report', FALSE);
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_non_resident_report
  ON public.non_resident_sessions;

CREATE TRIGGER trg_notify_non_resident_report
  AFTER UPDATE ON public.non_resident_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_officials_of_non_resident_report();


-- ============================================================================
-- VERIFY
-- ============================================================================
-- Simulate a report and confirm notifications land:
--
--   UPDATE public.non_resident_sessions
--   SET status = 'reported'
--   WHERE phone = '09000000003';
--
--   SELECT n.title, n.body, p.email, p.position, n.created_at
--   FROM public.notifications n
--   JOIN public.profiles p ON p.id = n.user_id
--   WHERE n.type = 'non_resident_report'
--   ORDER BY n.created_at DESC;
