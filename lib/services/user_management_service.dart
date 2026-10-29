import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/user_model.dart';

class UserManagementService {
  final _supabase = SupabaseService.instance;

  /// Get all users in a barangay (for admin).
  Future<List<UserModel>> getUsersByBarangay(
    String barangayId, {
    int limit = 1000,
    int offset = 0,
  }) async {
    final data = await _supabase.client
        .from('profiles')
        .select('*, barangays(name)')
        .eq('barangay_id', barangayId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((json) => UserModel.fromJson(json)).toList();
  }

  /// Get all users (for superadmin).
  Future<List<UserModel>> getAllUsers({int limit = 1000, int offset = 0}) async {
    final data = await _supabase.client
        .from('profiles')
        .select('*, barangays(name)')
        .order('created_at', ascending: false)
        // Bounded: this is every profile in Lipa City, and it was fetched in
        // full each time the superadmin opened the users screen.
        .range(offset, offset + limit - 1);

    return (data as List).map((json) => UserModel.fromJson(json)).toList();
  }

  /// Residents awaiting in-person verification.
  ///
  /// Pass `null` for city-wide (superadmin). Filtered server-side rather than
  /// by the caller: the superadmin screen used to fetch *every* profile and
  /// pick the pending ones out in Dart, which meant the queue was only ever as
  /// complete as the row limit on that fetch — an applicant could sit
  /// unverified and invisible simply because 200 newer accounts existed.
  Future<List<UserModel>> getPendingVerifications([String? barangayId]) async {
    var q = _supabase.client
        .from('profiles')
        .select('*, barangays(name)');
    if (barangayId != null) q = q.eq('barangay_id', barangayId);
    final data = await q
        .eq('is_verified', false)
        // Residents only. Non-residents no longer register or await approval —
        // they use the passwordless one-time flow. Legacy unverified
        // `non_resident` profiles are intentionally excluded so officials
        // aren't asked to approve accounts from a retired signup path.
        .eq('role', 'resident')
        .order('created_at', ascending: false);

    return (data as List).map((json) => UserModel.fromJson(json)).toList();
  }

  /// Every barangay-hall and superadmin account. `null` = city-wide.
  ///
  /// Server-filtered for the same reason as [getPendingVerifications]: derived
  /// from a truncated "all users" fetch, an official whose account predates the
  /// newest N profiles would simply not appear on the officials tab.
  Future<List<UserModel>> getStaffAccounts([String? barangayId]) async {
    var q = _supabase.client.from('profiles').select('*, barangays(name)');
    if (barangayId != null) q = q.eq('barangay_id', barangayId);
    final data = await q
        .inFilter('role', ['admin', 'superadmin'])
        .order('created_at', ascending: false)
        .limit(1000);
    return (data as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Resident accounts. `null` = city-wide.
  Future<List<UserModel>> getResidentAccounts([String? barangayId]) async {
    var q = _supabase.client.from('profiles').select('*, barangays(name)');
    if (barangayId != null) q = q.eq('barangay_id', barangayId);
    final data = await q
        .eq('role', 'resident')
        .order('created_at', ascending: false)
        .limit(1000);
    return (data as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Realtime signal that a profile in this barangay changed.
  ///
  /// Used as a "something changed, refetch" trigger rather than as the data
  /// itself — the emission carries raw rows with no `barangays(name)` join,
  /// and the screens need the join.
  ///
  /// Pass null for city-wide (superadmin).
  ///
  /// ⚠️ Delivers nothing at all if `profiles` is missing from the
  /// `supabase_realtime` publication, and does so **without any error**. That
  /// is why every caller also uses LiveRefreshMixin: realtime is the fast
  /// path, not the guarantee.
  Stream<List<Map<String, dynamic>>> subscribeToProfiles(String? barangayId) {
    final stream =
        _supabase.client.from('profiles').stream(primaryKey: ['id']);
    // `.eq` must precede `.limit` — the builder narrows type as it chains.
    // Bounded for the same reason as the incident streams: `.stream()`
    // re-emits the whole matched set on every change.
    return barangayId == null
        ? stream.limit(30)
        : stream.eq('barangay_id', barangayId).limit(30);
  }

  /// Verify a non-resident user.
  Future<void> verifyUser(String userId) async {
    await _supabase.client.from('profiles').update({
      'is_verified': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Lock / unlock a user account.
  /// §8 - sends an ID submission back for another attempt.
  ///
  /// This is NOT locking the account, and the distinction matters: an unreadable
  /// photo is a mistake, not misconduct. Locking someone for a blurry ID leaves
  /// them stuck with no route to being verified and no idea why. Clearing the
  /// submission returns them to the upload screen so they can simply retake it.
  ///
  /// Verification status is untouched - they were never verified, and they
  /// still are not.
  ///
  /// Clears all three photographs, not just the front. Clearing one would put
  /// the resident back on a screen showing two ticks and one gap, implying the
  /// two ticked photos were accepted — when the reviewer may have rejected the
  /// set precisely because they did not match each other.
  Future<void> rejectIdSubmission(String userId) async {
    await _supabase.client.from('profiles').update({
      'id_photo_url': null,
      'id_back_url': null,
      'id_selfie_url': null,
      'id_submitted_at': null,
    }).eq('id', userId);
  }

  Future<void> toggleLockUser(String userId, bool lock) async {
    await _supabase.client.from('profiles').update({
      'is_locked': lock,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Apply a false-report strike to a user.
  /// Returns the new strike count and the expiry DateTime (null if permanent lock).
  Future<({int strikes, DateTime? expiresAt, bool isPermanent})> applyFalseReportStrike(
      String userId) async {
    final row = await _supabase.client
        .from('profiles')
        .select('false_report_strikes')
        .eq('id', userId)
        .single();

    final currentStrikes = (row['false_report_strikes'] as int? ?? 0);
    final newStrikes = currentStrikes + 1;

    DateTime? expiresAt;
    bool isPermanent = false;

    if (newStrikes == 1) {
      expiresAt = DateTime.now().add(const Duration(days: 7));
    } else if (newStrikes == 2) {
      expiresAt = DateTime.now().add(const Duration(days: 30));
    } else {
      isPermanent = true;
    }

    await _supabase.client.from('profiles').update({
      'false_report_strikes': newStrikes,
      'strike_expires_at': expiresAt?.toIso8601String(),
      if (isPermanent) 'is_locked': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);

    return (strikes: newStrikes, expiresAt: expiresAt, isPermanent: isPermanent);
  }

  /// Correct a user's contact details.
  ///
  /// Officials get this because the details are operational, not cosmetic: a
  /// mistyped house number sends a responder to the wrong street, and until
  /// now the only person who could fix it was the resident who typed it wrong.
  ///
  /// Deliberately narrow — name, phone, address only. Role, position,
  /// verification and lock state each have their own method so that changing
  /// someone's authority can never happen by way of "editing their details".
  Future<void> updateUserDetails({
    required String userId,
    required String fullName,
    required String phone,
    String? address,
  }) async {
    await _supabase.client.from('profiles').update({
      'full_name': fullName,
      'phone': phone,
      'address': address,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Promote an existing account to barangay hall personnel.
  ///
  /// There is no "create an account" here on purpose. Making one would mean an
  /// official choosing someone else's password — the new tanod could not
  /// change it without knowing it, and the official would know a credential
  /// that logs in as them. So the person registers themselves like anyone
  /// else, and the captain grants the role afterwards.
  ///
  /// Role and position go in one statement because the
  /// `profiles_position_requires_staff_role` constraint rejects a position on
  /// a resident — two separate updates would fail on whichever ran first.
  Future<void> promoteToStaff(String userId, String position) async {
    await _supabase.client.from('profiles').update({
      'role': 'admin',
      'position': position,
      'is_verified': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Change a user's role (superadmin only).
  Future<void> changeUserRole(String userId, String newRole) async {
    await _supabase.client.from('profiles').update({
      'role': newRole,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Return an official to resident status.
  ///
  /// Role and position drop together because
  /// `profiles_position_requires_staff_role` forbids a resident holding a job
  /// title - clearing only the role makes the whole update fail.
  Future<void> demoteToResident(String userId) async {
    await _supabase.client.from('profiles').update({
      'role': 'resident',
      'position': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Assign or clear a barangay hall position (secretary, captain, tanod,
  /// staff). Pass null to remove the title.
  ///
  /// The account must already be on the admin/superadmin tier — the DB
  /// constraint `profiles_position_requires_staff_role` rejects giving a
  /// position to a resident.
  Future<void> setUserPosition(String userId, String? position) async {
    await _supabase.client.from('profiles').update({
      'position': position,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Roster of barangay hall personnel — everyone holding a position.
  /// Feeds the per-barangay roster and personnel headcount.
  Future<List<UserModel>> getBarangayPersonnel(String barangayId) async {
    final data = await _supabase.client
        .from('profiles')
        .select('*, barangays(name)')
        .eq('barangay_id', barangayId)
        .not('position', 'is', null)
        .order('position');

    return (data as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get user count by barangay.
  ///
  /// Counted server-side. This used to select the `id` of every profile in the
  /// barangay and take `.length` of the result — downloading one row per
  /// resident to render a single number.
  Future<int> getUserCount(String barangayId) => _supabase.client
      .from('profiles')
      .count(CountOption.exact)
      .eq('barangay_id', barangayId);

  /// Headline user counts for the analytics screen (§10).
  ///
  /// Goes through the `get_user_stats` RPC rather than reading `profiles`
  /// directly: it is SECURITY DEFINER, so an official gets the aggregate
  /// without needing SELECT permission on every profile row in their barangay.
  ///
  /// Pass `null` for city-wide (superadmin).
  ///
  /// Deliberately not caught here — the caller shows a retry, and swallowing
  /// this would render zeroes that look like real data.
  Future<UserStats> getUserStats({String? barangayId}) async {
    final data = await _supabase.client.rpc(
      'get_user_stats',
      params: {'p_barangay_id': barangayId},
    );

    // Postgres RETURNS TABLE arrives as a one-element list.
    final rows = data as List;
    if (rows.isEmpty) return const UserStats.empty();
    return UserStats.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Age-bracket counts for the analytics screen (§10).
  ///
  /// Returns bracket → count, e.g. `{'45_and_over': 12, 'unknown': 40}`.
  /// The `unknown` bracket is every profile with no date of birth; it exists
  /// because DOB capture only started 2026-08-11, so historical accounts have
  /// none and would otherwise be silently miscounted as young.
  Future<Map<String, int>> getAgeDemographics({String? barangayId}) async {
    final data = await _supabase.client.rpc(
      'get_age_demographics',
      params: {'p_barangay_id': barangayId},
    );

    return {
      for (final row in (data as List))
        (row as Map<String, dynamic>)['bracket'] as String:
            (row['user_count'] as num).toInt(),
    };
  }
}

/// Headline counts returned by `get_user_stats`.
class UserStats {
  final int totalUsers;
  final int residents;
  final int nonResidents;
  final int personnel;
  final int age45Plus;

  const UserStats({
    required this.totalUsers,
    required this.residents,
    required this.nonResidents,
    required this.personnel,
    required this.age45Plus,
  });

  const UserStats.empty()
      : totalUsers = 0,
        residents = 0,
        nonResidents = 0,
        personnel = 0,
        age45Plus = 0;

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
        residents: (json['residents'] as num?)?.toInt() ?? 0,
        nonResidents: (json['non_residents'] as num?)?.toInt() ?? 0,
        personnel: (json['personnel'] as num?)?.toInt() ?? 0,
        age45Plus: (json['age_45_plus'] as num?)?.toInt() ?? 0,
      );
}
