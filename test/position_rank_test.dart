import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/utils/constants.dart';
import 'package:barangay_safety_app/utils/permissions.dart';

/// §9 — the structural guards added 2026-08-18.
///
/// These pin an escalation path that was live: any account with
/// `managePositions` could set the Captain to `staff` (read-only, and
/// unrecoverable without a superadmin) or mint new Captains at will.
UserModel _u(String id, String role, String? position) => UserModel(
      id: id,
      email: '$id@test.local',
      fullName: id,
      phone: '09000000000',
      role: role,
      position: position,
      barangayId: 'brgy-1',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final captain = _u('captain', 'admin', UserPosition.captain);
  final secretary = _u('secretary', 'admin', UserPosition.secretary);
  final secretary2 = _u('secretary2', 'admin', UserPosition.secretary);
  final tanod = _u('tanod', 'admin', UserPosition.tanod);
  final staff = _u('staff', 'admin', UserPosition.staff);
  final legacy = _u('legacy', 'admin', null); // no title = full access
  final resident = _u('resident', 'resident', null);
  final superadmin = _u('super', 'superadmin', null);

  group('the reported escalation is closed', () {
    test('a secretary cannot demote the captain to staff', () {
      expect(
        canSetPositionOf(secretary, captain,
            newPosition: UserPosition.staff, checkNewPosition: true),
        isFalse,
      );
    });

    test('a secretary cannot promote anyone to captain', () {
      expect(
        canSetPositionOf(secretary, tanod,
            newPosition: UserPosition.captain, checkNewPosition: true),
        isFalse,
      );
    });

    test('a secretary cannot promote THEMSELVES to captain', () {
      expect(
        canSetPositionOf(secretary, secretary,
            newPosition: UserPosition.captain, checkNewPosition: true),
        isFalse,
      );
    });

    test('a secretary cannot clear a position — that grants full access', () {
      expect(
        canSetPositionOf(secretary, secretary,
            newPosition: null, checkNewPosition: true),
        isFalse,
      );
    });

    test('a secretary cannot touch a peer secretary', () {
      expect(canSetPositionOf(secretary, secretary2), isFalse);
    });

    test('a secretary cannot lock the captain out', () {
      expect(canLockAccount(secretary, captain), isFalse);
    });

    test('nobody can lock themselves out', () {
      expect(canLockAccount(captain, captain), isFalse);
      expect(canLockAccount(superadmin, superadmin), isFalse);
    });
  });

  group('legitimate work still works', () {
    test('a secretary can appoint a tanod', () {
      expect(
        canSetPositionOf(secretary, tanod,
            newPosition: UserPosition.tanod, checkNewPosition: true),
        isTrue,
      );
    });

    test('a secretary can appoint a resident', () {
      expect(
        canSetPositionOf(secretary, resident,
            newPosition: UserPosition.secretary, checkNewPosition: true),
        isTrue,
      );
    });

    test('a secretary can step themselves down', () {
      expect(
        canSetPositionOf(secretary, secretary,
            newPosition: UserPosition.tanod, checkNewPosition: true),
        isTrue,
      );
    });

    test('the captain can still do everything below them', () {
      expect(
        canSetPositionOf(captain, secretary,
            newPosition: UserPosition.staff, checkNewPosition: true),
        isTrue,
      );
      expect(canLockAccount(captain, secretary), isTrue);
    });

    test('the superadmin is exempt and can always repair a barangay', () {
      expect(
        canSetPositionOf(superadmin, captain,
            newPosition: UserPosition.captain, checkNewPosition: true),
        isTrue,
      );
      expect(canLockAccount(superadmin, captain), isTrue);
    });

    test('a secretary keeps every operational power', () {
      // The owner's decision stands — seniority governs the hierarchy only.
      for (final c in [
        Capability.verifyReport,
        Capability.assignOfficial,
        Capability.dispatchResponders,
        Capability.resolveIncident,
        Capability.raiseFullBlast,
        Capability.flagFalseReport,
      ]) {
        expect(can(secretary, c), isTrue, reason: '$c should stay allowed');
      }
    });
  });

  group('ranks that are easy to get backwards', () {
    test('no position outranks captain, because it means full access', () {
      expect(positionRank(null), greaterThanOrEqualTo(positionRank(UserPosition.captain)));
      expect(canSetPositionOf(secretary, legacy), isFalse);
    });

    test('tanod and staff cannot manage positions at all', () {
      expect(canSetPositionOf(tanod, staff), isFalse);
      expect(canSetPositionOf(staff, tanod), isFalse);
    });

    test('assignable list never exceeds the actor rank', () {
      expect(assignablePositions(secretary), isNot(contains(UserPosition.captain)));
      expect(assignablePositions(secretary), contains(UserPosition.secretary));
      expect(assignablePositions(captain), contains(UserPosition.captain));
      expect(assignablePositions(tanod), isEmpty);
      expect(assignablePositions(superadmin), equals(UserPosition.all));
    });
  });
}
