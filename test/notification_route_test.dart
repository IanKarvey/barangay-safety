import 'package:barangay_safety_app/models/notification_model.dart';
import 'package:barangay_safety_app/utils/notification_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Notification taps carry their destination through a single opaque string.
///
/// Android hands back exactly one `payload`, so the type has to travel inside
/// it. Previously only the incident id was sent — so a notification with no
/// incident ("your ID could not be read, please submit again") arrived with a
/// null payload and tapping it did nothing. Telling someone to act and then
/// refusing to take them anywhere is the worst version of that message.
///
/// Pinned here because a mistake is invisible from the outside: the
/// notification still appears, still taps, and still goes nowhere.
void main() {
  NotificationModel n(String type, {String? incidentId}) => NotificationModel(
        id: 'n1',
        userId: 'u1',
        title: 't',
        body: 'b',
        type: type,
        incidentId: incidentId,
        isRead: false,
        createdAt: DateTime(2026, 8, 25),
      );

  /// Runs [body] with a real BuildContext that has no AuthProvider above it.
  ///
  /// That is deliberately the awkward case: `incidentRouteForCurrentUser`
  /// falls back to the read-only route when no provider is in scope, and a
  /// notification tap really can arrive before the app has one.
  Future<void> withContext(
    WidgetTester tester,
    void Function(BuildContext ctx) body,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (ctx) {
          captured = ctx;
          return const SizedBox.shrink();
        }),
      ),
    );
    body(captured);
  }

  group('payload round-trip', () {
    test('type and incident id both survive', () {
      expect(encodeNotificationPayload('comment', 'abc-123'), 'comment|abc-123');
    });

    test('a missing incident id is encoded, not dropped', () {
      // The whole point: this used to be null and the tap died.
      final p = encodeNotificationPayload('id_rejected', null);
      expect(p, 'id_rejected|');
      expect(p, isNotEmpty);
    });

    test('the separator survives a UUID', () {
      const id = '11111111-2222-3333-4444-555555555555';
      final p = encodeNotificationPayload('status_change', id);
      expect(p.substring(0, p.indexOf('|')), 'status_change');
      expect(p.substring(p.indexOf('|') + 1), id);
    });
  });

  group('every type has somewhere to go', () {
    testWidgets('an ID sent back opens the screen that can retake it',
        (tester) async {
      await withContext(tester, (ctx) {
        final target = notificationTargetFor(ctx, n('id_rejected'));
        expect(target, isNotNull);
        expect(target!.route, '/pending-verification');
        expect(target.arguments, isNull);
      });
    });

    testWidgets('a role change goes home, where the new abilities appear',
        (tester) async {
      await withContext(tester, (ctx) {
        expect(notificationTargetFor(ctx, n('role_granted'))?.route, '/');
      });
    });

    testWidgets('a strike without an incident opens the profile',
        (tester) async {
      await withContext(tester, (ctx) {
        expect(notificationTargetFor(ctx, n('false_report_strike'))?.route,
            '/edit-profile');
      });
    });

    testWidgets('a strike WITH an incident opens that incident instead',
        (tester) async {
      await withContext(tester, (ctx) {
        final target = notificationTargetFor(
            ctx, n('false_report_strike', incidentId: 'i9'));
        expect(target!.arguments, 'i9');
        expect(target.route, isNot('/edit-profile'));
      });
    });

    testWidgets('an unknown type with no incident goes nowhere',
        (tester) async {
      await withContext(tester, (ctx) {
        // Returning a route here would push a screen that explains nothing.
        expect(notificationTargetFor(ctx, n('something_new')), isNull);
      });
    });

    testWidgets('an unknown type WITH an incident still opens the incident',
        (tester) async {
      await withContext(tester, (ctx) {
        final target =
            notificationTargetFor(ctx, n('something_new', incidentId: 'i7'));
        expect(target!.arguments, 'i7');
      });
    });
  });

  group('decoding what a tap hands back', () {
    testWidgets('a legacy bare id still routes', (tester) async {
      // Notifications delivered by older builds are still in people's trays.
      await withContext(tester, (ctx) {
        expect(targetFromPayload(ctx, 'old-incident-id')?.arguments,
            'old-incident-id');
      });
    });

    testWidgets('an encoded id_rejected reaches the retake screen',
        (tester) async {
      await withContext(tester, (ctx) {
        final target = targetFromPayload(
            ctx, encodeNotificationPayload('id_rejected', null));
        expect(target?.route, '/pending-verification');
      });
    });

    testWidgets('an empty payload is refused rather than guessed at',
        (tester) async {
      await withContext(tester, (ctx) {
        expect(targetFromPayload(ctx, ''), isNull);
      });
    });
  });
}
