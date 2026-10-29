import 'package:flutter/widgets.dart';

import '../models/notification_model.dart';
import 'incident_route.dart';

/// Where tapping a notification should take you.
///
/// ## Why this exists
///
/// Tapping only ever worked for notifications that carried an `incidentId`.
/// Everything else — an ID sent back for a retake, a role granted — marked
/// itself read and went nowhere. That is the worst possible response to
/// "Your ID could not be read, please submit again": it tells someone to act
/// and then refuses to take them anywhere to act.
///
/// ## The rule
///
/// A notification is a message about something. Tapping it should show you
/// that thing, or the closest screen from which you can do something about it.
/// If neither exists, return null and let the caller simply mark it read
/// rather than pushing a route that explains nothing.
class NotificationTarget {
  const NotificationTarget(this.route, {this.arguments});

  final String route;
  final Object? arguments;
}

/// Resolves [n] to a destination, or null when there is nowhere useful to go.
///
/// [context] is needed because incident notifications route by role — an
/// official gets the manage screen, everyone else the read-only one. See
/// [incidentRouteForCurrentUser]; that split closed an authorisation hole
/// where residents landed on a page with Mark Resolved and Delete on their own
/// case.
NotificationTarget? notificationTargetFor(
  BuildContext context,
  NotificationModel n,
) {
  switch (n.type) {
    // The resident must be able to retake the photo from the message telling
    // them to retake the photo.
    case 'id_rejected':
      return const NotificationTarget('/pending-verification');

    // Their permissions just changed. Home is where the new abilities appear,
    // and the shell re-reads the profile on the way in.
    case 'role_granted':
      return const NotificationTarget('/');

    // A strike changes what the account may do, and the notification names the
    // report that caused it — so the report is the useful destination when it
    // is attached, and the profile when it is not.
    case 'false_report_strike':
      if (n.incidentId != null) break;
      return const NotificationTarget('/edit-profile');
  }

  // Everything incident-shaped: comment, status_change, assigned, full_blast,
  // new_critical.
  if (n.incidentId != null) {
    return NotificationTarget(
      incidentRouteForCurrentUser(context),
      arguments: n.incidentId,
    );
  }

  // Nothing sensible to open. The caller still marks it read.
  return null;
}

/// Packs what a tap needs into the single string a system notification can
/// carry.
///
/// Android hands back exactly one opaque `payload` string, so the type has to
/// travel inside it. Previously only the incident id was sent, which meant a
/// push with no incident — an ID sent back for a retake — arrived with a null
/// payload and tapping it did nothing at all.
///
/// Format is `type|incidentId`, with the id empty when there isn't one. `|`
/// is safe: types are fixed identifiers and ids are UUIDs.
String encodeNotificationPayload(String type, String? incidentId) =>
    '$type|${incidentId ?? ''}';

/// Reverses [encodeNotificationPayload] and resolves a destination.
///
/// Tolerates a bare incident id with no separator, because notifications
/// delivered by older builds are still sitting in people's trays.
NotificationTarget? targetFromPayload(BuildContext context, String payload) {
  final i = payload.indexOf('|');
  if (i < 0) {
    // Legacy payload: an incident id on its own.
    return payload.isEmpty
        ? null
        : NotificationTarget(
            incidentRouteForCurrentUser(context),
            arguments: payload,
          );
  }

  final type = payload.substring(0, i);
  final rawId = payload.substring(i + 1);
  return notificationTargetFor(
    context,
    NotificationModel(
      id: '',
      userId: '',
      title: '',
      body: '',
      type: type,
      incidentId: rawId.isEmpty ? null : rawId,
      isRead: true,
      createdAt: DateTime.now(),
    ),
  );
}
