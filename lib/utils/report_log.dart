import '../models/incident_model.dart';
import 'response_stats.dart';

/// One line of the report log: a single report, with who reported it, when, who
/// responded, and how long it took — everything an official asks about a case.
///
/// Built only from fields that are safe to print. It deliberately has NO
/// description (a walk-in's contact number is typed into it), no coordinates, no
/// address or landmark, no phone, email, ID or photo.
class ReportLogEntry {
  const ReportLogEntry({
    required this.id,
    required this.reporterName,
    required this.reporterIsResident,
    required this.barangay,
    required this.category,
    required this.severity,
    required this.status,
    required this.reportedAt,
    required this.responderName,
    this.firstResponseAt,
    this.dispatchedAt,
    this.onSceneAt,
    this.finishedAt,
    this.escalationLevel = 0,
    this.overdue = false,
    required this.now,
  });

  final String id;
  final String reporterName;

  /// False for a walk-in who reported through the non-resident flow.
  final bool reporterIsResident;
  final String barangay;
  final String category;
  final int severity;
  final String status;
  final DateTime reportedAt;

  /// Who took it (assigned to / volunteered). Null when nobody has.
  final String? responderName;

  final DateTime? firstResponseAt;
  final DateTime? dispatchedAt;
  final DateTime? onSceneAt;

  /// When it was resolved or closed. Null while it is still open — and null for
  /// an old case that was finished before the finish time was being recorded: it
  /// is never filled in with a guess.
  final DateTime? finishedAt;
  final int escalationLevel;
  final bool overdue;

  /// "Now" when the log was built, so "open for" is stable for one export.
  final DateTime now;

  String get shortId => id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

  bool get isFlagged => status == 'flagged';
  bool get isFinishedStatus => status == 'resolved' || status == 'closed';

  /// Finished and the finish time is on record.
  bool get isFinished => isFinishedStatus && finishedAt != null;

  /// Not finished and not set aside: still waiting on somebody.
  bool get isOpen => !isFinishedStatus && !isFlagged;

  /// Report to first official action.
  Duration? get timeToFirstResponse {
    final t = firstResponseAt?.difference(reportedAt);
    return (t == null || t.isNegative) ? null : t;
  }

  /// Report to finished. THE number the owner asked for: how long it took.
  Duration? get timeToFinish {
    if (!isFinished) return null;
    final t = finishedAt!.difference(reportedAt);
    return t.isNegative ? null : t;
  }

  /// How long it has been waiting, for a report that is still open.
  Duration? get openFor {
    if (!isOpen) return null;
    final t = now.difference(reportedAt);
    return t.isNegative ? Duration.zero : t;
  }

  String get statusLabel => switch (status) {
        'pending' => 'Pending',
        'verified' => 'Verified',
        'assigned' => 'Assigned',
        'responding' || 'in_progress' => 'Responding',
        'on_scene' => 'On scene',
        'resolved' => 'Resolved',
        'closed' => 'Closed',
        'flagged' => 'Flagged',
        _ => status,
      };

  String get severityWord => switch (severity) {
        4 => 'Critical',
        3 => 'High',
        2 => 'Medium',
        _ => 'Low',
      };

  /// One plain sentence about the outcome, for the screen and the Word report.
  String get outcome {
    if (isFlagged) return 'Set aside (flagged)';
    if (isFinished) return 'Finished in ${humanDuration(timeToFinish!)}';
    if (isFinishedStatus) return 'Finished (time not recorded)';
    return 'Still open - waiting ${humanDuration(openFor!)}';
  }
}

/// `45 s`, `12 min`, `2 h 14 min`, `3 d 4 h`. Short enough for a table cell,
/// exact enough to read a response time off.
String humanDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  if (total < 60) return '$total s';
  final minutes = total ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final restMin = minutes % 60;
  if (hours < 24) return restMin == 0 ? '$hours h' : '$hours h $restMin min';
  final days = hours ~/ 24;
  final restH = hours % 24;
  return restH == 0 ? '$days d' : '$days d $restH h';
}

/// Who reported it, in words.
///
/// A resident has a profile name. A walk-in has none on the incident itself — the
/// name lives on their one-time session — but the report was created with the
/// sentence "<name> reported an emergency via the non-resident flow", so the name
/// is read back from the start of it. ONLY the name is taken: the rest of that
/// sentence holds the visitor's phone number and must never reach an export.
String reporterNameFor(IncidentModel i) {
  final name = i.reporterName?.trim();
  if (name != null && name.isNotEmpty) return name;
  if (i.isNonResidentReport) {
    final m = RegExp(r'^(.{1,60}?) reported an emergency via the non-resident flow')
        .firstMatch(i.description);
    final parsed = m?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty && !RegExp(r'\d{5,}').hasMatch(parsed)) {
      return '$parsed (walk-in)';
    }
    return 'Walk-in visitor';
  }
  return 'Unknown';
}

/// Earliest real action on a report: the recorded first action, else the first
/// time anyone verified, assigned or dispatched it. These are timestamps the
/// database really stamped, not estimates.
DateTime? firstResponseTime(IncidentModel i) {
  final candidates = <DateTime>[
    for (final t in [i.firstActionAt, i.verifiedAt, i.assignedAt, i.respondingAt, i.onSceneAt])
      if (t != null) t,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort();
  return candidates.first;
}

/// Turns incidents into log lines, newest report first.
List<ReportLogEntry> buildReportLog(
  Iterable<IncidentModel> incidents, {
  DateTime? now,
  bool Function(IncidentModel)? isOverdue,
}) {
  final at = now ?? DateTime.now();
  final entries = [
    for (final i in incidents)
      ReportLogEntry(
        id: i.id,
        reporterName: reporterNameFor(i),
        reporterIsResident: !i.isNonResidentReport,
        barangay: i.barangayName ?? '',
        category: i.category,
        severity: i.severityLevel,
        status: i.status,
        reportedAt: i.createdAt,
        responderName: i.assignedToName,
        firstResponseAt: firstResponseTime(i),
        dispatchedAt: i.respondingAt,
        onSceneAt: i.onSceneAt,
        finishedAt: (i.status == 'resolved' || i.status == 'closed')
            ? (i.resolvedAt ?? i.closedAt)
            : null,
        escalationLevel: i.escalationLevel,
        overdue: isOverdue?.call(i) ?? false,
        now: at,
      ),
  ]..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
  return entries;
}

/// Totals over a log, for the report's summary and the per-responder table.
class ReportLogStats {
  ReportLogStats._({
    required this.total,
    required this.finished,
    required this.open,
    required this.flagged,
    required this.timeToFinish,
    required this.timeToFirstResponse,
    required this.fastest,
    required this.slowest,
    required this.byResponder,
  });

  factory ReportLogStats.from(List<ReportLogEntry> log) {
    final finished = log.where((e) => e.timeToFinish != null).toList();
    ReportLogEntry? fastest, slowest;
    for (final e in finished) {
      if (fastest == null || e.timeToFinish! < fastest.timeToFinish!) fastest = e;
      if (slowest == null || e.timeToFinish! > slowest.timeToFinish!) slowest = e;
    }

    final groups = <String, List<ReportLogEntry>>{};
    for (final e in log) {
      final who = e.responderName;
      if (who != null && who.isNotEmpty) groups.putIfAbsent(who, () => []).add(e);
    }
    final responders = [
      for (final g in groups.entries)
        ResponderStats(
          name: g.key,
          taken: g.value.length,
          finished: g.value.where((e) => e.timeToFinish != null).length,
          stillOpen: g.value.where((e) => e.isOpen).length,
          timeToFinish: summarizeSeconds(g.value.map((e) => e.timeToFinish?.inSeconds)),
        ),
    ]..sort((a, b) => b.taken != a.taken ? b.taken.compareTo(a.taken) : a.name.compareTo(b.name));

    return ReportLogStats._(
      total: log.length,
      finished: finished.length,
      open: log.where((e) => e.isOpen).length,
      flagged: log.where((e) => e.isFlagged).length,
      timeToFinish: summarizeSeconds(log.map((e) => e.timeToFinish?.inSeconds)),
      timeToFirstResponse: summarizeSeconds(log.map((e) => e.timeToFirstResponse?.inSeconds)),
      fastest: fastest,
      slowest: slowest,
      byResponder: responders,
    );
  }

  final int total;
  final int finished;
  final int open;
  final int flagged;
  final DurationSummary timeToFinish;
  final DurationSummary timeToFirstResponse;
  final ReportLogEntry? fastest;
  final ReportLogEntry? slowest;
  final List<ResponderStats> byResponder;
}

class ResponderStats {
  const ResponderStats({
    required this.name,
    required this.taken,
    required this.finished,
    required this.stillOpen,
    required this.timeToFinish,
  });

  final String name;
  final int taken;
  final int finished;
  final int stillOpen;
  final DurationSummary timeToFinish;
}
