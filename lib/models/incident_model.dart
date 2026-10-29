import '../utils/severity.dart';
class IncidentModel {
  final String id;
  /// Null for non-resident emergencies. PART 4 of
  /// `migration_batch_2026_08_09.sql` relaxed `incidents.reporter_id` to
  /// nullable so anonymous reports could become real incident records —
  /// anonymous users deliberately have no `profiles` row. Their identity
  /// lives in `reported_by_session_id` instead.
  final String? reporterId;
  final String? reporterName;
  /// Reporter's contact number, so an official can phone them back. Comes
  /// from the profiles join; null for non-resident incidents, which carry
  /// their contact on the session instead.
  final String? reporterPhone;
  final String barangayId;
  final String? barangayName;
  final String category;
  final String description;
  final int severityLevel;
  final String status;
  final double latitude;
  final double longitude;
  final String? address;
  final String? landmark;
  final List<String> photoUrls;
  final List<String> videoUrls;
  final String? assignedTo;
  final String? assignedToName;
  final String? resolutionNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// §5 integrity signals. Advisory only — they never blocked the report.
  /// False on anything filed before 2026-08-16 because it was never
  /// checked, which is not the same as having been checked and cleared.
  final bool reportedViaVpn;
  final bool locationMocked;

  /// §4.2 — set only when an official confirmed this report describes an
  /// emergency already on file. Never written by the detector itself: two real
  /// emergencies can happen next door to each other, and auto-merging loses
  /// one of them.
  final String? duplicateOfId;

  /// §4.2 — when a human last ruled on a duplicate suggestion for this report,
  /// either way. Stops the same pair being re-suggested forever, which is how
  /// a suggestion becomes noise officials learn to dismiss on sight.
  final DateTime? duplicateCheckedAt;

  /// §4.3 — 64-bit dHash of the first photo, 16 hex chars. Perceptual:
  /// compare with `ImageHashService.hammingDistance`, never with `==`.
  final String? photoHash;

  /// Set when the report came through the non-resident one-time flow.
  /// Mutually exclusive with [reporterId] — see PART 4 of
  /// `migration_batch_2026_08_09.sql`.
  final String? reportedBySessionId;
  final DateTime? resolvedAt;

  /// Per-stage timestamps, stamped automatically by the DB trigger
  /// `stamp_incident_stage()`. These are what make response time measurable
  /// per stage instead of inferred from a single `updatedAt`.
  final DateTime? verifiedAt;
  final DateTime? assignedAt;
  final DateTime? respondingAt;
  final DateTime? onSceneAt;
  final DateTime? closedAt;

  /// First time an official opened the report. Recorded, but it does not count
  /// as a response and never stops the escalation clock.
  final DateTime? firstSeenAt;

  /// First official ACTION (status change, assignment, or a message to the
  /// resident), stamped by a database trigger. While this is null the report is
  /// "unanswered" and the 5/10/15-minute escalation applies.
  final DateTime? firstActionAt;

  /// Highest unanswered-report tier reached: 0 none, 1 / 2 / 3. Level 3 is the
  /// "Unattended / Last Resort" state.
  final int escalationLevel;

  IncidentModel({
    required this.id,
    this.reporterId,
    this.reporterName,
    this.reporterPhone,
    required this.barangayId,
    this.barangayName,
    required this.category,
    required this.description,
    required this.severityLevel,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.address,
    this.landmark,
    this.photoUrls = const [],
    this.videoUrls = const [],
    this.assignedTo,
    this.assignedToName,
    this.resolutionNotes,
    required this.createdAt,
    required this.updatedAt,
    this.duplicateOfId,
    this.duplicateCheckedAt,
    this.photoHash,
    this.reportedViaVpn = false,
    this.locationMocked = false,
    this.reportedBySessionId,
    this.resolvedAt,
    this.verifiedAt,
    this.assignedAt,
    this.respondingAt,
    this.onSceneAt,
    this.closedAt,
    this.firstSeenAt,
    this.firstActionAt,
    this.escalationLevel = 0,
  });

  factory IncidentModel.fromJson(Map<String, dynamic> json) {
    List<String> photos = [];
    List<String> videos = [];

    if (json['incident_media'] != null) {
      final media = json['incident_media'] as List;
      for (final m in media) {
        final url = m['photo_url'] as String;
        final type = m['media_type'] as String? ?? 'photo';
        if (type == 'video') {
          videos.add(url);
        } else {
          photos.add(url);
        }
      }
    } else if (json['photo_urls'] != null) {
      photos = List<String>.from(json['photo_urls'] as List);
    }

    return IncidentModel(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String?,
      reporterName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : json['reporter_name'] as String?,
      reporterPhone: json['profiles'] != null
          ? json['profiles']['phone'] as String?
          : json['reporter_phone'] as String?,
      barangayId: json['barangay_id'] as String,
      barangayName: json['barangays'] != null
          ? json['barangays']['name'] as String?
          : json['barangay_name'] as String?,
      category: json['category'] as String,
      description: json['description'] as String,
      severityLevel: json['severity_level'] as int,
      status: json['status'] as String? ?? 'pending',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      landmark: json['landmark'] as String?,
      photoUrls: photos,
      videoUrls: videos,
      assignedTo: json['assigned_to'] as String?,
      assignedToName: json['assigned_profile'] != null
          ? json['assigned_profile']['full_name'] as String?
          : json['assigned_to_name'] as String?,
      resolutionNotes: json['resolution_notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      duplicateOfId: json['duplicate_of_id'] as String?,
      duplicateCheckedAt: _parseDate(json['duplicate_checked_at']),
      photoHash: json['photo_hash'] as String?,
      reportedViaVpn: json['reported_via_vpn'] as bool? ?? false,
      locationMocked: json['location_mocked'] as bool? ?? false,
      reportedBySessionId: json['reported_by_session_id'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      verifiedAt: _parseDate(json['verified_at']),
      assignedAt: _parseDate(json['assigned_at']),
      respondingAt: _parseDate(json['responding_at']),
      onSceneAt: _parseDate(json['on_scene_at']),
      closedAt: _parseDate(json['closed_at']),
      firstSeenAt: _parseDate(json['first_seen_at']),
      firstActionAt: _parseDate(json['first_action_at']),
      escalationLevel: (json['escalation_level'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  Map<String, dynamic> toJson() {
    return {
      'reporter_id': reporterId,
      'barangay_id': barangayId,
      'category': category,
      'description': description,
      'severity_level': severityLevel,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'landmark': landmark,
      'assigned_to': assignedTo,
      'resolution_notes': resolutionNotes,
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  IncidentModel copyWith({
    String? status,
    int? severityLevel,
    String? assignedTo,
    String? assignedToName,
    String? resolutionNotes,
    DateTime? resolvedAt,
  }) {
    return IncidentModel(
      id: id,
      reporterId: reporterId,
      reporterName: reporterName,
      reporterPhone: reporterPhone,
      barangayId: barangayId,
      barangayName: barangayName,
      category: category,
      description: description,
      severityLevel: severityLevel ?? this.severityLevel,
      status: status ?? this.status,
      latitude: latitude,
      longitude: longitude,
      address: address,
      landmark: landmark,
      photoUrls: photoUrls,
      videoUrls: videoUrls,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      duplicateOfId: duplicateOfId,
      duplicateCheckedAt: duplicateCheckedAt,
      photoHash: photoHash,
      reportedViaVpn: reportedViaVpn,
      locationMocked: locationMocked,
      reportedBySessionId: reportedBySessionId,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      verifiedAt: verifiedAt,
      assignedAt: assignedAt,
      respondingAt: respondingAt,
      onSceneAt: onSceneAt,
      closedAt: closedAt,
      firstSeenAt: firstSeenAt,
      firstActionAt: firstActionAt,
      escalationLevel: escalationLevel,
    );
  }

  /// A walk-up emergency rather than a registered resident's report.
  ///
  /// Matters for more than a label: there is no account to notify, no strike
  /// that can be applied, and the reporter is reachable only by phone. An
  /// official needs to know which kind of case this is before acting on it.
  bool get isNonResidentReport => reportedBySessionId != null;

  /// Nobody has acted on this report yet — the state the 5/10/15-minute
  /// escalation watches. Reports filed before the tracking existed also have no
  /// `first_action_at`, so only a still-pending one counts as unanswered.
  bool get isUnanswered => status == 'pending' && firstActionAt == null;

  /// Escalated all the way with still no response ("Unattended / Last Resort").
  bool get isUnattended => isUnanswered && escalationLevel >= 3;

  bool get isPending => status == 'pending';
  bool get isInProgress => status == 'in_progress';
  bool get isResolved => status == 'resolved';
  bool get isFlagged => status == 'flagged';
  bool get isCritical => Severity.isCritical(severityLevel);
  int get totalMedia => photoUrls.length + videoUrls.length;

  // ── Six-stage tracking ──────────────────────────────────────────────────
  /// How far along the response is, 0–5, for the resident-facing tracker.
  ///
  /// Legacy `in_progress` maps to "Responders En Route" so incidents filed
  /// before the six-stage flow existed still render sensibly rather than
  /// collapsing to stage 0.
  int get stageIndex => switch (status) {
        'pending' => 0,
        'verified' => 1,
        'assigned' => 2,
        'responding' || 'in_progress' => 3,
        'on_scene' => 4,
        'resolved' || 'closed' => 5,
        _ => 0, // flagged — handled separately by the UI
      };

  /// Timestamp for a given stage, or null if it hasn't happened yet.
  /// Falls back to `resolvedAt` for the final stage so older incidents that
  /// predate `closed_at` still show a completion time.
  DateTime? timestampForStage(int index) => switch (index) {
        0 => createdAt,
        1 => verifiedAt,
        2 => assignedAt,
        3 => respondingAt,
        4 => onSceneAt,
        5 => closedAt ?? resolvedAt,
        _ => null,
      };

  /// Total time from report to resolution, or time elapsed so far.
  Duration get elapsed =>
      (closedAt ?? resolvedAt ?? DateTime.now()).difference(createdAt);
  /// True when an official folded this report into another one. Such reports
  /// stay in the database with their own reporter and photos — they are hidden
  /// from the working queue, not deleted.
  bool get isDuplicate => duplicateOfId != null;

  /// True when a human has ruled on duplicate suggestions for this report,
  /// either way. Distinct from [isDuplicate]: "checked and it is not one" and
  /// "not yet checked" must not look the same to the detector.
  bool get duplicateReviewed => duplicateCheckedAt != null;

}
