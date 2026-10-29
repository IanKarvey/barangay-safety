import '../models/incident_model.dart';
import '../models/user_model.dart';
import 'permissions.dart';

/// §6 — the safety net for cases that were handled in person but never closed
/// in the system.
///
/// The scenario this exists for: a tanod settles a dispute on the street, tells
/// the reporter it's sorted, and never reopens the app. The case sits at
/// "Responding" forever. Nobody is doing anything wrong — the record just
/// silently drifts away from reality, and every statistic built on it is wrong.
///
/// Note this measures from `updatedAt`, not `createdAt`. A case worked on
/// steadily for three days is healthy; one touched three days ago is not. The
/// existing `slaStatus()` badge measures from creation and answers a different
/// question — "is this taking too long?" rather than "has everyone forgotten
/// about this?" — so both are kept.
class StaleCases {
  /// How long an active case may go untouched before it is worth asking about.
  ///
  /// A full day rather than a few hours: barangay work is not desk work, and
  /// nagging someone every afternoon about a case they are actively handling
  /// is how a prompt gets ignored permanently.
  static const Duration threshold = Duration(hours: 24);

  static bool isStale(IncidentModel incident) {
    // Only cases someone has actually taken on. A pending report nobody has
    // picked up is a different problem, already visible as "awaiting action".
    if (!_isActive(incident)) return false;
    return DateTime.now().difference(incident.updatedAt) >= threshold;
  }

  static bool _isActive(IncidentModel incident) => switch (incident.status) {
        'assigned' || 'responding' || 'in_progress' || 'on_scene' => true,
        _ => false,
      };

  /// Stale cases [user] is responsible for.
  ///
  /// Reuses [visibleIncidents], so a Tanod is only ever asked about their own
  /// cases while a Secretary or Captain sees every forgotten one in the
  /// barangay — they are the ones who can chase it.
  static List<IncidentModel> forUser(
    UserModel? user,
    List<IncidentModel> incidents,
  ) {
    final mine = visibleIncidents(user, incidents);
    final stale = mine.where(isStale).toList();
    // Longest-forgotten first — that is the one most likely to be wrong.
    stale.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return stale;
  }

  /// Whole days since the case was last touched, for the prompt text.
  static int daysSince(IncidentModel incident) =>
      DateTime.now().difference(incident.updatedAt).inDays;
}
