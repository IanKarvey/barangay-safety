-- ############################################################################
-- WITHDRAWN 2026-08-21 - DO NOT RUN
--
-- The premise below is false. `notifications` already had a working DELETE
-- policy all along:
--
--   Users can delete own notifications | DELETE | PERMISSIVE | authenticated
--                                      | (user_id = auth.uid())
--
-- This file only added a second, functionally identical policy. That duplicate
-- has been dropped. The April bug was a realtime race that _dismissedIds
-- already fixed - not a permissions failure.
--
-- Kept in the repo as a record of the mistake rather than deleted: the claim
-- reached the requirements doc and the update log, and the correction should
-- be traceable from the file that caused it.
-- ############################################################################

-- ============================================================================
-- Notifications: let a user delete their own rows.
-- 2026-08-18
-- ============================================================================
--
-- ## The bug this fixes
--
-- Swiping a notification away removed it from the screen and it came back on
-- the next app start. The app was issuing the DELETE correctly; the row was
-- never removed because `notifications` has RLS enabled with SELECT and UPDATE
-- policies but no DELETE policy. PostgREST reports a policy-denied delete as a
-- success with zero rows affected, so the client had no error to show and the
-- failure was invisible from the app side.
--
-- NotificationProvider now also persists dismissed ids locally, so the symptom
-- is already gone for users. That is a backstop for offline and for older app
-- builds — this policy is the actual fix, and without it every dismissal is
-- carried forever in the device's SharedPreferences instead of being resolved.
--
-- Safe to run more than once.
-- ============================================================================

-- Confirm the table is protected at all. If RLS were off, the missing DELETE
-- policy would not have blocked anything — and a much bigger problem would be
-- that any signed-in user could read everyone's notifications.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- A user may delete only rows addressed to them. Scoped by `user_id` and not
-- by role: officials have no business clearing a resident's alerts, and a
-- resident has no business clearing anyone's.
DROP POLICY IF EXISTS "Users can delete their own notifications"
  ON public.notifications;

CREATE POLICY "Users can delete their own notifications"
  ON public.notifications
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================================
-- Verification — run this after applying. Expect four rows: SELECT, INSERT,
-- UPDATE and the DELETE policy created above. If DELETE is the only one
-- listed, the other policies are missing and notifications are readable by
-- anyone signed in; say so before shipping.
-- ============================================================================
SELECT cmd, policyname
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'notifications'
ORDER  BY cmd;
