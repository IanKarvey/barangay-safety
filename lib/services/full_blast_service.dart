import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/incident_model.dart';
import 'notification_service.dart';
import 'sms_service.dart';
import 'user_management_service.dart';
import '../utils/severity.dart';

/// §14 — the mass alert for incidents that cannot wait for someone to open the
/// app and notice.
///
/// ## Who receives it
///
/// Barangay hall personnel only — anyone holding a `position`. Per **SD-1**,
/// contacting PNP, BFP or an ambulance is the hall's job, done by a person, off
/// this system. The app's responsibility ends at making sure the hall knows.
///
/// ## Why it bypasses the usual routing
///
/// Ordinary notifications go to the one official handling a case. A fire or an
/// active robbery is different: the cost of five people being told unnecessarily
/// is a moment's interruption, and the cost of nobody being told is measured in
/// property and lives. So this ignores assignment entirely and tells everyone.
///
/// That asymmetry is also why it is reserved for **severity 1 (critical)**
/// automatically. Blasting every report would train people to ignore the alert,
/// which is the same as not having one.
class FullBlastService {
  final _notifications = NotificationService();
  final _users = UserManagementService();
  final _sms = SmsService();

  /// Alerts every member of [barangayId]'s hall about [incident].
  ///
  /// Returns how many people were reached, or 0 on failure. **Never throws** —
  /// see [raiseForNewIncident] for why that matters.
  Future<int> raise({
    required String barangayId,
    required IncidentModel incident,
    required String reason,
  }) async {
    try {
      final personnel = await _users.getBarangayPersonnel(barangayId);
      if (personnel.isEmpty) {
        // Worth a log rather than silence: a barangay with nobody holding a
        // position cannot be alerted at all, and that is a configuration
        // problem someone needs to fix.
        debugPrint('FullBlast: no personnel assigned in barangay $barangayId');
        return 0;
      }

      final where = incident.address ?? 'an unmapped location';

      await _notifications.sendBulk(
        userIds: personnel.map((u) => u.id).toList(),
        title: 'EMERGENCY — $reason',
        body: '${incident.category} at $where. Open now.',
        type: 'full_blast',
        incidentId: incident.id,
      );

      // §11 — a second delivery path, not a replacement. Push needs the app
      // installed, notifications permitted and data switched on; a tanod on a
      // basic plan with mobile data off still gets the SMS. Deliberately not
      // awaited into the result: the in-app alert is already delivered, and an
      // unconfigured or failing SMS provider must not make a successful blast
      // report as a failure.
      // Kept strictly inside the GSM-7 character set and under 160 characters.
      // SMS bills per 160-char segment in GSM-7, but a SINGLE character outside
      // it (an em-dash, a curly quote) forces the whole message to UCS-2, where
      // a segment is only 70 characters. One dash would silently double the
      // cost of every blast to every recipient, forever.
      //
      // The address is the only variable-length part and reverse geocoding can
      // return very long strings, so it is truncated rather than trusted.
      final smsWhere = where.length > 80 ? '${where.substring(0, 77)}...' : where;
      unawaited(_sms.send(
        phones: personnel.map((u) => u.phone).toList(),
        message: 'BARANGAY SAFETY: ${incident.category} at $smsWhere. '
            'Check the app now.',
      ));

      return personnel.length;
    } catch (e) {
      debugPrint('FullBlast: could not alert barangay $barangayId: $e');
      return 0;
    }
  }

  /// Fires automatically when a critical report is filed.
  ///
  /// Deliberately swallows every failure. This runs immediately after a
  /// resident submits a report, and an alert that fails must never surface as
  /// "your report failed" — the report is already saved, and telling a
  /// frightened person their emergency did not go through would be both untrue
  /// and cruel. A missed blast degrades to the normal flow, where the Secretary
  /// still sees the report in their queue.
  Future<void> raiseForNewIncident(IncidentModel incident) async {
    // Critical only. Blasting every report trains people to ignore the
    // alert, which is the same as not having one.
    if (!Severity.isCritical(incident.severityLevel)) return;
    await raise(
      barangayId: incident.barangayId,
      incident: incident,
      reason: 'Critical report just filed',
    );
  }
}
