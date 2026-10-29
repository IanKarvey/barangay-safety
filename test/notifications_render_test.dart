import 'package:barangay_safety_app/models/notification_model.dart';
import 'package:barangay_safety_app/providers/notification_provider.dart';
import 'package:barangay_safety_app/screens/shared/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/render.dart';

// Only what the screen reads is real; the rest would reach for Supabase.
class _FakeNotifications extends ChangeNotifier implements NotificationProvider {
  _FakeNotifications(this._items);
  final List<NotificationModel> _items;

  @override
  List<NotificationModel> get notifications => _items;
  @override
  bool get isLoading => false;
  @override
  int get unreadCount => _items.where((n) => !n.isRead).length;
  @override
  Future<void> load() async {}
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}

  final dismissed = <String>[];
  @override
  Future<void> dismiss(String id) async => dismissed.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationModel _n(String id, String type, String title, String body,
        int minutesAgo, {bool read = false}) =>
    NotificationModel(
      id: id,
      userId: 'u1',
      title: title,
      body: body,
      type: type,
      incidentId: 'i-$id',
      isRead: read,
      createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  setUpAll(loadRealFonts);

  final items = [
    _n('1', 'escalation', 'Escalated to the City Administrator',
        'Vandalism in Barangay 3 is still unresolved after 51 hours and needs city-level intervention.', 12),
    _n('2', 'escalation', 'Report overdue',
        'Public Disturbance in Barangay 1 is overdue (26 hours). Supervisors have been alerted.', 95),
    _n('3', 'assigned', 'New assignment', 'You were assigned a Noise Disturbance report.', 210),
    _n('4', 'new_critical', 'New critical report', 'Domestic Violence reported in Barangay 2.', 600, read: true),
    _n('5', 'comment', 'New update on a report', 'The resident replied to your question.', 1500, read: true),
  ];

  Future<_FakeNotifications> pump(WidgetTester tester, Size size) async {
    final fake = _FakeNotifications(items);
    useSize(tester, size);
    await tester.pumpWidget(renderApp(
      const NotificationsScreen(),
      extraProviders: [
        ChangeNotifierProvider<NotificationProvider>.value(value: fake),
      ],
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return fake;
  }

  testWidgets('on a desktop each notification has a visible Remove button',
      (tester) async {
    final fake = await pump(tester, const Size(1280, 760));
    await snap(tester, 'notifications_1280');

    expect(find.text('Remove'), findsNWidgets(5));
    expect(find.text('Swipe to remove'), findsNothing,
        reason: 'a swipe hint means nothing with a mouse');

    await tester.tap(find.text('Remove').first);
    await tester.pump();
    expect(fake.dismissed, ['1']);
  });

  testWidgets('on a phone it keeps the swipe hint and adds no button',
      (tester) async {
    await pump(tester, const Size(400, 760));
    await snap(tester, 'notifications_400');

    expect(find.text('Remove'), findsNothing);
    expect(find.text('Swipe to remove'), findsWidgets);
  });

  testWidgets('the desktop list is a centred column, not edge to edge',
      (tester) async {
    await pump(tester, const Size(1280, 760));

    final tile = tester.getRect(find.text('Report overdue').first);
    expect(tile.left, greaterThan(200),
        reason: 'content should sit well inside a 1280px window');
  });
}
