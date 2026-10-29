import 'package:barangay_safety_app/models/barangay_model.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/screens/shared/emergency_contacts_screen.dart';
import 'package:barangay_safety_app/services/emergency_contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/render.dart';

class _Service implements EmergencyContactsService {
  final Map<String?, List<EmergencyContact>> byScope = {
    'b3': [
      const EmergencyContact(id: '1', barangayId: 'b3', label: 'Brgy 3 Tanod Hall', category: 'rescue', phoneNumber: '(043) 111 1111', sortOrder: 1),
      const EmergencyContact(id: '2', barangayId: 'b3', label: 'Lipa Police', category: 'police', phoneNumber: '+639000000001', sortOrder: 2),
    ],
    null: [
      const EmergencyContact(id: '9', barangayId: null, label: 'City Fire Station', category: 'fire', phoneNumber: '(043) 757 4168', sortOrder: 1),
    ],
  };
  final calls = <String>[];

  @override
  Future<List<EmergencyContact>> manageList(String? barangayId) async {
    calls.add('list:$barangayId');
    return List.of(byScope[barangayId] ?? const []);
  }

  @override
  Future<void> add({
    required String? barangayId,
    required String label,
    required String category,
    required String phoneNumber,
    int sortOrder = 0,
  }) async {
    calls.add('add:$barangayId:$label:$phoneNumber');
    (byScope[barangayId] ??= []).add(EmergencyContact(
      id: 'new${calls.length}', barangayId: barangayId, label: label,
      category: category, phoneNumber: phoneNumber, sortOrder: sortOrder));
  }

  @override
  Future<void> update(EmergencyContact c) async {
    calls.add('update:${c.id}:${c.isActive}:${c.sortOrder}');
    final list = byScope[c.barangayId]!;
    list[list.indexWhere((e) => e.id == c.id)] = c;
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    for (final l in byScope.values) {
      l.removeWhere((e) => e.id == id);
    }
  }

  @override
  Future<List<EmergencyContact>> numbersFor(String barangayId) async => const [];
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);
  final UserModel _user;
  @override
  UserModel? get user => _user;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

UserModel _user({bool superAdmin = false}) => UserModel(
      id: 'u1', email: 'a@x.ph', fullName: 'Juan', phone: '0917',
      role: superAdmin ? 'superadmin' : 'admin', position: 'captain',
      barangayId: superAdmin ? null : 'b3', isVerified: true,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  setUpAll(loadRealFonts);

  group('phone number check', () {
    test('accepts how people actually write numbers', () {
      for (final ok in ['911', '(043) 757 4168', '+63 900 000 0001', '0917-123-4567', '+639000000001']) {
        expect(validateContactNumber(ok), isNull, reason: ok);
      }
    });

    test('rejects what would not dial', () {
      expect(validateContactNumber(''), isNotNull);
      expect(validateContactNumber('   '), isNotNull);
      expect(validateContactNumber('call 911'), isNotNull);
      expect(validateContactNumber('12'), isNotNull);
      expect(validateContactNumber('1234567890123456'), isNotNull);
      expect(validateContactNumber('09+17'), isNotNull);
      expect(validateContactNumber('++6391'), isNotNull);
    });
  });

  Future<_Service> mount(WidgetTester tester, {UserModel? user}) async {
    useSize(tester, const Size(900, 900));
    final service = _Service();
    await tester.pumpWidget(renderApp(
      EmergencyContactsScreen(
        service: service,
        barangays: [
          BarangayModel(id: 'b3', name: 'Barangay 3', centerLat: 13.9, centerLng: 121.1, createdAt: DateTime(2026)),
          BarangayModel(id: 'b7', name: 'Barangay 7', centerLat: 13.9, centerLng: 121.1, createdAt: DateTime(2026)),
        ],
      ),
      extraProviders: [ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(user ?? _user()))],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return service;
  }

  testWidgets('an admin sees only their own barangay\'s numbers', (tester) async {
    final s = await mount(tester);
    expect(s.calls.first, 'list:b3');
    expect(find.text('Brgy 3 Tanod Hall'), findsOneWidget);
    expect(find.text('Lipa Police'), findsOneWidget);
    expect(find.text('City Fire Station'), findsNothing);
    expect(find.text('Whose numbers'), findsNothing);
    expect(tester.takeException(), isNull);
    await snap(tester, 'emergency_contacts_admin');
  });

  testWidgets('adding a number validates, then saves into the admin\'s own barangay', (tester) async {
    final s = await mount(tester);
    await tester.tap(find.text('Add a number'));
    await tester.pump(const Duration(milliseconds: 300));

    // Empty form: both fields complain, nothing is saved.
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a phone number'), findsOneWidget);
    expect(s.calls.where((c) => c.startsWith('add')), isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Barangay Clinic');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), 'call me');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('digits only'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '(043) 222 3333');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(s.calls, contains('add:b3:Barangay Clinic:(043) 222 3333'));
    expect(find.text('Barangay Clinic'), findsOneWidget);
  });

  testWidgets('hiding a number keeps it but stops residents seeing it', (tester) async {
    final s = await mount(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.calls, contains('update:1:false:1'));
  });

  testWidgets('removing asks first', (tester) async {
    final s = await mount(tester);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove this number?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.calls.where((c) => c.startsWith('delete')), isEmpty);

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.calls, contains('delete:1'));
    expect(find.text('Brgy 3 Tanod Hall'), findsNothing);
  });

  testWidgets('moving a number down swaps the order residents see', (tester) async {
    final s = await mount(tester);
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.calls, containsAll(['update:1:true:2', 'update:2:true:1']));
  });

  testWidgets('a superadmin starts at city level and can switch barangay', (tester) async {
    final s = await mount(tester, user: _user(superAdmin: true));
    expect(s.calls.first, 'list:null');
    expect(find.text('City Fire Station'), findsOneWidget);
    expect(find.text('Whose numbers'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Barangay 3').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.calls, contains('list:b3'));
    expect(find.text('Brgy 3 Tanod Hall'), findsOneWidget);
  });

  testWidgets('an empty list explains the fallback', (tester) async {
    useSize(tester, const Size(900, 900));
    final service = _Service()..byScope['b3'] = [];
    await tester.pumpWidget(renderApp(
      EmergencyContactsScreen(service: service, barangays: const []),
      extraProviders: [ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(_user()))],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Residents will see the city numbers'), findsOneWidget);
  });
}
