import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/user_model.dart';

class AuthService {
  final _supabase = SupabaseService.instance;

  // ── Sign Up ─────────────────────────────────────────────────────────────
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String barangayId,
    String? address,
    DateTime? dateOfBirth,
    String? guardianName,
    String? guardianPhone,
    String? guardianRelationship,
    String role = 'resident',
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'barangay_id': barangayId,
        'address': address ?? '',
        // Read out of raw_user_meta_data by the profiles_copy_dob trigger
        // (supabase/migration_dob_capture.sql). Date-only, no timezone, so a
        // birthday cannot shift across midnight.
        'date_of_birth': dateOfBirth == null
            ? ''
            : dateOfBirth.toIso8601String().split('T').first,
        // RA 10173 requires consent to be demonstrable. Stamped at the moment
        // it was given, not inferred later from the account's existence.
        'privacy_consent_at': DateTime.now().toUtc().toIso8601String(),
        // §8 minors. Rides in metadata rather than being written after signUp
        // because a registration that needs email confirmation has no session
        // yet — and those are exactly the accounts most likely to be a
        // minor's. `profiles_copy_guardian` copies these across on INSERT.
        'guardian_name': guardianName ?? '',
        'guardian_phone': guardianPhone ?? '',
        'guardian_relationship': guardianRelationship ?? '',
        // Only stamped when a guardian was actually named. An empty timestamp
        // here would record consent nobody gave.
        'guardian_consent_at': (guardianName == null || guardianName.isEmpty)
            ? ''
            : DateTime.now().toUtc().toIso8601String(),
      },
    );

    if (response.user == null) {
      throw Exception('Sign up failed. Please try again.');
    }

    return response;
  }

  /// §12 — has this phone number already registered?
  ///
  /// One person with several accounts is how the false-report strike system
  /// gets defeated: collect three strikes, sign up again, carry on. Phone is
  /// the practical identifier — it is the number an official actually dials,
  /// and a second SIM costs something where a second email is free.
  ///
  /// Goes through the `phone_already_registered` RPC because the caller is
  /// mid-signup and has no permission to read `profiles`. Digits are compared
  /// server-side, so 0917-123-4567 and 09171234567 are the same number.
  ///
  /// **Returns false when the check itself fails.** A registration must never
  /// be blocked because a lookup timed out — a warning that fails open is a
  /// warning; one that fails closed is an outage.
  Future<bool> isPhoneAlreadyRegistered(String phone) async {
    try {
      final result = await _supabase.client
          .rpc('phone_already_registered', params: {'p_phone': phone});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // signUpNonResident() removed 2026-08-08 — see NonResidentService for the
  // passwordless one-time flow that replaced it.

  /// RA 10173 right to erasure.
  ///
  /// Records the request rather than deleting anything. Erasure is not
  /// absolute here: incident reports are the barangay's operational and legal
  /// record of an emergency and its response, and deleting a reporter must not
  /// erase the fact that a fire was reported and answered. A human resolves it
  /// properly — anonymise the reporter, keep the incident.
  Future<void> requestDataDeletion(String userId) async {
    await _supabase.client.from('profiles').update({
      'data_deletion_requested_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  // ── Sign In ─────────────────────────────────────────────────────────────
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    // Check if account is locked
    final profile = await getProfile(response.user!.id);
    if (profile != null && profile.isLocked) {
      await signOut();
      throw Exception(
        'Your account has been locked. Please contact your barangay office.',
      );
    }

    return response;
  }

  // ── Sign Out ────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ── Password Reset ──────────────────────────────────────────────────────
  /// Sends the recovery email.
  ///
  /// `redirectTo` is not optional in practice. Without it Supabase uses the
  /// project's Site URL, so the link opened a web page instead of the app and
  /// the deep-link handler never ran — the reported "reset link lands on
  /// Login" (2026-09-15).
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConfig.passwordResetRedirect,
    );
  }

  // ── Get Profile ─────────────────────────────────────────────────────────
  Future<UserModel?> getProfile(String userId) async {
    final data = await _supabase.client
        .from('profiles')
        .select('*, barangays(name)')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  // ── Update Profile ──────────────────────────────────────────────────────
  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    await _supabase.client.from('profiles').update(updates).eq('id', userId);
  }

  // ── Get Current Profile ─────────────────────────────────────────────────
  Future<UserModel?> getCurrentProfile() async {
    final user = _supabase.currentUser;
    if (user == null) return null;
    return getProfile(user.id);
  }

  // ── Listen to Auth State ────────────────────────────────────────────────
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
