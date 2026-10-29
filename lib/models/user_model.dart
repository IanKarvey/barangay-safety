class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String role; // superadmin, admin, resident, non_resident
  /// Barangay hall job title — secretary, captain, tanod, staff.
  /// Null for residents/non-residents and for officials with no title assigned.
  /// This is a label for display/assignment, not a permission grant — see [role].
  final String? position;
  final String? barangayId;
  final String? barangayName;
  final String? address;
  final String? profilePhotoUrl;
  /// Storage object path (not a URL) of the submitted ID. Sensitive personal
  /// information under RA 10173 — the bucket is private; reviewers fetch a
  /// short-lived signed URL. See `IdVerificationService`.
  final String? idPhotoUrl;

  /// Back of the ID — security features, signature panel, control numbers.
  /// The front alone is the easy half to fake.
  final String? idBackUrl;

  /// Selfie holding the ID, so a reviewer can see the holder matches the
  /// document. **Not a biometric template**: no face embedding is computed or
  /// stored anywhere in this system, which keeps it clear of RA 10173's
  /// biometric provisions while answering the same question.
  final String? idSelfieUrl;

  /// Which document was presented — see [IdType]. A school ID identifies a
  /// minor, which pulls in the guardian requirement below.
  final String? idType;

  /// When the ID was submitted, so a review queue can be ordered by how long
  /// someone has been waiting to be allowed to report an emergency.
  final DateTime? idSubmittedAt;

  /// Parent/guardian details, required when [dateOfBirth] puts the account
  /// under 18. RA 10173 requires guardian consent to process a minor's data —
  /// the app already knew the age and did nothing with it until 2026-08-18.
  final String? guardianName;
  final String? guardianPhone;
  final String? guardianRelationship;

  /// Timestamp, not a boolean, for the same reason as `privacyConsentAt`: a
  /// boolean keeps saying yes after the notice is revised.
  final DateTime? guardianConsentAt;
  final bool isVerified;

  /// Set when the user exercised their RA 10173 right to erasure.
  final DateTime? dataDeletionRequestedAt;
  final bool isLocked;
  final int falseReportStrikes;
  final DateTime? strikeExpiresAt;

  /// Live position, published only while [isSharingLocation] is true. Lets a
  /// reporter watch help approach instead of guessing whether anyone is coming.
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastLocationAt;

  /// Opt-in and session-scoped. An official is never tracked merely for being
  /// logged in — nothing is written or served while this is false.
  final bool isSharingLocation;

  /// Stored rather than an age number, so it never goes stale.
  final DateTime? dateOfBirth;

  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    this.position,
    this.barangayId,
    this.barangayName,
    this.address,
    this.profilePhotoUrl,
    this.idPhotoUrl,
    this.idBackUrl,
    this.idSelfieUrl,
    this.idType,
    this.idSubmittedAt,
    this.guardianName,
    this.guardianPhone,
    this.guardianRelationship,
    this.guardianConsentAt,
    this.isVerified = false,
    this.dataDeletionRequestedAt,
    this.isLocked = false,
    this.falseReportStrikes = 0,
    this.strikeExpiresAt,
    this.lastLat,
    this.lastLng,
    this.lastLocationAt,
    this.isSharingLocation = false,
    this.dateOfBirth,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'resident',
      position: json['position'] as String?,
      barangayId: json['barangay_id'] as String?,
      barangayName: json['barangays'] != null
          ? json['barangays']['name'] as String?
          : json['barangay_name'] as String?,
      address: json['address'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      idPhotoUrl: json['id_photo_url'] as String?,
      idSubmittedAt: json['id_submitted_at'] != null
          ? DateTime.parse(json['id_submitted_at'] as String)
          : null,
      isVerified: json['is_verified'] as bool? ?? false,
      dataDeletionRequestedAt: json['data_deletion_requested_at'] != null
          ? DateTime.parse(json['data_deletion_requested_at'] as String)
          : null,
      isLocked: json['is_locked'] as bool? ?? false,
      falseReportStrikes: json['false_report_strikes'] as int? ?? 0,
      strikeExpiresAt: json['strike_expires_at'] != null
          ? DateTime.parse(json['strike_expires_at'] as String)
          : null,
      lastLat: (json['last_lat'] as num?)?.toDouble(),
      lastLng: (json['last_lng'] as num?)?.toDouble(),
      lastLocationAt: json['last_location_at'] != null
          ? DateTime.parse(json['last_location_at'] as String)
          : null,
      isSharingLocation: json['is_sharing_location'] as bool? ?? false,
      idBackUrl: json['id_back_url'] as String?,
      idSelfieUrl: json['id_selfie_url'] as String?,
      idType: json['id_type'] as String?,
      guardianName: json['guardian_name'] as String?,
      guardianPhone: json['guardian_phone'] as String?,
      guardianRelationship: json['guardian_relationship'] as String?,
      guardianConsentAt: json['guardian_consent_at'] != null
          ? DateTime.parse(json['guardian_consent_at'] as String)
          : null,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'position': position,
      'barangay_id': barangayId,
      'address': address,
      'profile_photo_url': profilePhotoUrl,
      'id_photo_url': idPhotoUrl,
      'is_verified': isVerified,
      'is_locked': isLocked,
      'false_report_strikes': falseReportStrikes,
      'strike_expires_at': strikeExpiresAt?.toIso8601String(),
      'last_lat': lastLat,
      'last_lng': lastLng,
      'last_location_at': lastLocationAt?.toIso8601String(),
      'is_sharing_location': isSharingLocation,
      'id_back_url': idBackUrl,
      'id_selfie_url': idSelfieUrl,
      'id_type': idType,
      'guardian_name': guardianName,
      'guardian_phone': guardianPhone,
      'guardian_relationship': guardianRelationship,
      'guardian_consent_at': guardianConsentAt?.toIso8601String(),
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? fullName,
    String? phone,
    String? role,
    String? position,
    String? barangayId,
    String? barangayName,
    String? address,
    String? profilePhotoUrl,
    String? idPhotoUrl,
    bool? isVerified,
    bool? isLocked,
    int? falseReportStrikes,
    DateTime? strikeExpiresAt,
    double? lastLat,
    double? lastLng,
    DateTime? lastLocationAt,
    bool? isSharingLocation,
    String? idBackUrl,
    String? idSelfieUrl,
    String? idType,
    String? guardianName,
    String? guardianPhone,
    String? guardianRelationship,
    DateTime? guardianConsentAt,
    DateTime? dateOfBirth,
  }) {
    return UserModel(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      position: position ?? this.position,
      barangayId: barangayId ?? this.barangayId,
      barangayName: barangayName ?? this.barangayName,
      address: address ?? this.address,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      idPhotoUrl: idPhotoUrl ?? this.idPhotoUrl,
      isVerified: isVerified ?? this.isVerified,
      isLocked: isLocked ?? this.isLocked,
      falseReportStrikes: falseReportStrikes ?? this.falseReportStrikes,
      strikeExpiresAt: strikeExpiresAt ?? this.strikeExpiresAt,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
      isSharingLocation: isSharingLocation ?? this.isSharingLocation,
      idBackUrl: idBackUrl ?? this.idBackUrl,
      idSelfieUrl: idSelfieUrl ?? this.idSelfieUrl,
      idType: idType ?? this.idType,
      guardianName: guardianName ?? this.guardianName,
      guardianPhone: guardianPhone ?? this.guardianPhone,
      guardianRelationship: guardianRelationship ?? this.guardianRelationship,
      guardianConsentAt: guardianConsentAt ?? this.guardianConsentAt,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => role == 'admin';
  bool get isResident => role == 'resident';
  bool get isNonResident => role == 'non_resident';
  bool get isOfficial => role == 'superadmin' || role == 'admin';

  // ── Barangay hall position (job title, not a permission) ────────────────
  bool get isSecretary => position == 'secretary';
  bool get isCaptain => position == 'captain';
  bool get isTanod => position == 'tanod';

  /// True if this account holds any barangay hall job title.
  bool get hasPosition => position != null;

  /// True if currently serving a temporary suspension from false report strike.
  bool get isActivelySuspended =>
      strikeExpiresAt != null && strikeExpiresAt!.isAfter(DateTime.now());

  /// Age in whole years, or null when no date of birth was captured.
  ///
  /// DOB collection only started 2026-08-11, so a null here means "unknown",
  /// never "adult" — every caller must treat the two differently or historical
  /// accounts get silently classified as adults.
  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  /// True only when the date of birth is known AND under 18.
  /// Unknown ages are deliberately not treated as minors — see [age].
  /// True when at least one of the three §8 ID photographs is on file.
  ///
  /// Used to decide whether to render the review strip. Deliberately "any"
  /// rather than "all three": a partial submission still needs looking at, and
  /// hiding it would leave an applicant invisible in the queue.
  bool get hasSubmittedId =>
      idPhotoUrl != null || idBackUrl != null || idSelfieUrl != null;

  bool get isMinor {
    final a = age;
    return a != null && a < 18;
  }

  /// A minor whose guardian has not consented yet. Drives the registration
  /// gate and the official's review checklist.
  bool get needsGuardianConsent => isMinor && guardianConsentAt == null;

  /// All three ID photographs are on file and ready to review.
  bool get hasCompleteIdSubmission =>
      idPhotoUrl != null && idBackUrl != null && idSelfieUrl != null;

  /// Something was submitted, but not everything.
  bool get hasPartialIdSubmission =>
      !hasCompleteIdSubmission &&
      (idPhotoUrl != null || idBackUrl != null || idSelfieUrl != null);
}