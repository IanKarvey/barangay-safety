import 'dart:math' as math;

/// A non-resident's one-time reporting session.
///
/// Non-residents sign in with just a contact number + name (no password), get
/// a 7-day window in which to file exactly ONE report, and are tracked live
/// while that report is in flight. See `supabase/migration_non_resident_sessions.sql`.
class NonResidentSessionModel {
  final String id;
  final String authUserId;
  final String phone;
  final String fullName;

  /// Auto-detected from GPS at sign-in — never manually chosen.
  final String? barangayId;
  final String? barangayName;

  /// active | reported | called | proof_ready | deployed | completed | disregarded
  final String status;

  final String? incidentId;

  final double? lastLat;
  final double? lastLng;
  final DateTime? lastLocationAt;

  /// True once the one allowed report has been filed.
  final bool hasReported;

  /// Logout is blocked while a report is in flight (anti-bogus measure).
  final bool logoutLocked;

  final String? disregardReason;

  /// The barangay official coming to them. Null until someone is assigned.
  final String? assignedOfficialId;

  /// True when the reporter could not complete the call — no load, no signal,
  /// or the dialer failed. Recorded honestly instead of marking them 'called',
  /// so the Secretary knows to phone OUT rather than wait for a call in.
  final bool callFailed;
  /// 'no_credits' | 'no_signal' | 'dialer_failed' | 'other'
  final String? callFailedReason;

  /// Photo/video evidence the barangay reviews before deploying anyone.
  final String? proofUrl;
  /// 'photo' or 'video'.
  final String? proofType;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Session resets after this — they may report again once it passes.
  final DateTime expiresAt;

  NonResidentSessionModel({
    required this.id,
    required this.authUserId,
    required this.phone,
    required this.fullName,
    this.barangayId,
    this.barangayName,
    required this.status,
    this.incidentId,
    this.lastLat,
    this.lastLng,
    this.lastLocationAt,
    this.hasReported = false,
    this.logoutLocked = false,
    this.disregardReason,
    this.proofUrl,
    this.proofType,
    this.assignedOfficialId,
    this.callFailed = false,
    this.callFailedReason,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  factory NonResidentSessionModel.fromJson(Map<String, dynamic> json) {
    return NonResidentSessionModel(
      id: json['id'] as String,
      authUserId: json['auth_user_id'] as String,
      phone: json['phone'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      barangayId: json['barangay_id'] as String?,
      barangayName: json['barangays'] != null
          ? json['barangays']['name'] as String?
          : json['barangay_name'] as String?,
      status: json['status'] as String? ?? 'active',
      incidentId: json['incident_id'] as String?,
      lastLat: (json['last_lat'] as num?)?.toDouble(),
      lastLng: (json['last_lng'] as num?)?.toDouble(),
      lastLocationAt: json['last_location_at'] != null
          ? DateTime.parse(json['last_location_at'] as String)
          : null,
      hasReported: json['has_reported'] as bool? ?? false,
      logoutLocked: json['logout_locked'] as bool? ?? false,
      disregardReason: json['disregard_reason'] as String?,
      assignedOfficialId: json['assigned_official_id'] as String?,
      callFailed: json['call_failed'] as bool? ?? false,
      callFailedReason: json['call_failed_reason'] as String?,
      proofUrl: json['proof_url'] as String?,
      proofType: json['proof_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_user_id': authUserId,
      'phone': phone,
      'full_name': fullName,
      'barangay_id': barangayId,
      'status': status,
      'incident_id': incidentId,
      'last_lat': lastLat,
      'last_lng': lastLng,
      'last_location_at': lastLocationAt?.toIso8601String(),
      'has_reported': hasReported,
      'logout_locked': logoutLocked,
      'disregard_reason': disregardReason,
      'assigned_official_id': assignedOfficialId,
      'call_failed': callFailed,
      'call_failed_reason': callFailedReason,
      'proof_url': proofUrl,
      'proof_type': proofType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  NonResidentSessionModel copyWith({
    String? barangayId,
    String? barangayName,
    String? status,
    String? incidentId,
    double? lastLat,
    double? lastLng,
    DateTime? lastLocationAt,
    bool? hasReported,
    bool? logoutLocked,
    String? disregardReason,
    String? proofUrl,
    String? proofType,
    String? assignedOfficialId,
    bool? callFailed,
    String? callFailedReason,
    DateTime? expiresAt,
  }) {
    return NonResidentSessionModel(
      id: id,
      authUserId: authUserId,
      phone: phone,
      fullName: fullName,
      barangayId: barangayId ?? this.barangayId,
      barangayName: barangayName ?? this.barangayName,
      status: status ?? this.status,
      incidentId: incidentId ?? this.incidentId,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
      hasReported: hasReported ?? this.hasReported,
      logoutLocked: logoutLocked ?? this.logoutLocked,
      disregardReason: disregardReason ?? this.disregardReason,
      assignedOfficialId: assignedOfficialId ?? this.assignedOfficialId,
      callFailed: callFailed ?? this.callFailed,
      callFailedReason: callFailedReason ?? this.callFailedReason,
      proofUrl: proofUrl ?? this.proofUrl,
      proofType: proofType ?? this.proofType,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  // ── Status helpers ────────────────────────────────────────────────────
  bool get isActive => status == 'active';
  bool get isReported => status == 'reported';
  bool get hasCalled => status == 'called';
  bool get isProofReady => status == 'proof_ready';
  bool get isDeployed => status == 'deployed';
  bool get isCompleted => status == 'completed';
  bool get isDisregarded => status == 'disregarded';

  /// True once the session is over — no further action possible.
  bool get isClosed => isCompleted || isDisregarded;

  /// True while a report is in flight, i.e. the session must stay open and
  /// the user must stay in the app.
  bool get isInFlight =>
      isReported || hasCalled || isProofReady || isDeployed;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Whether the reporter may still cancel their own report.
  ///
  /// The cutoff is **deployment**. Up to that point cancelling is cheap and
  /// genuinely useful — a false alarm withdrawn early saves the barangay a
  /// trip, so it should stay easy. Once responders are `deployed` someone is
  /// physically travelling to them, and letting the reporter silently cancel
  /// at that moment is the worst case: the barangay keeps driving to an
  /// incident the app has already closed, or stands down a real emergency
  /// because a panicking reporter tapped cancel.
  ///
  /// After deployment they can still stand down — by calling the barangay, so
  /// a human confirms it.
  bool get canCancel =>
      !isClosed &&
      !isDeployed &&
      // The Secretary is actively reviewing their evidence — cancelling
      // mid-review wastes that work and can look like evidence being pulled.
      !isProofReady &&
      // A named official has been given this report and may already be
      // travelling, even before anyone taps Deploy. Locking only at 'deployed'
      // left a real window where someone was en route and the reporter could
      // still close the case under them.
      assignedOfficialId == null;

  /// Days remaining before the 7-day window resets.
  int get daysUntilReset {
    final diff = expiresAt.difference(DateTime.now()).inHours;
    return diff <= 0 ? 0 : (diff / 24).ceil();
  }

  bool get hasLocation => lastLat != null && lastLng != null;

  /// Kilometres from the Lipa City centre used for the coverage geofence.
  /// Null when no fix has arrived yet.
  ///
  /// Sign-in refuses anyone outside coverage, but a reporter can walk or drive
  /// out mid-session — the barangay needs to know that, since dispatching to
  /// someone 25km away is a different decision entirely.
  double? get distanceFromCoverageKm {
    if (!hasLocation) return null;

    const centerLat = 13.9411; // Lipa City
    const centerLng = 121.1632;
    const earthRadiusKm = 6371.0;

    double toRad(double d) => d * math.pi / 180.0;

    final dLat = toRad(lastLat! - centerLat);
    final dLng = toRad(lastLng! - centerLng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(centerLat)) *
            math.cos(toRad(lastLat!)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// True when the reporter has left the 20km coverage area mid-session.
  bool get isOutsideCoverage {
    final km = distanceFromCoverageKm;
    return km != null && km > 20.0;
  }

  /// True when the live location has gone stale — the Secretary should be
  /// warned that they may have lost the reporter.
  bool locationStaleAfter(Duration threshold) {
    if (lastLocationAt == null) return true;
    return DateTime.now().difference(lastLocationAt!) > threshold;
  }
}
