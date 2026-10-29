import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  DateTime? _suspensionExpiry;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get suspensionExpiry => _suspensionExpiry;
  bool get isAuthenticated => _user != null;
  bool get isSuperAdmin => _user?.isSuperAdmin ?? false;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isResident => _user?.isResident ?? false;
  bool get isOfficial => _user?.isOfficial ?? false;

  // ── Initialize — check if user is already logged in ───────────────────
  Future<void> initialize() async {
    _isLoading = true;
    _safeNotify();

    try {
      _user = await _authService.getCurrentProfile();
    } catch (e) {
      _user = null;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── Sign In ─────────────────────────────────────────────────────────────
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      await _authService.signIn(email: email, password: password);
      _user = await _authService.getCurrentProfile();

      // Check if user is suspended (flagged/locked) — sign them out and surface the error
      if (_user != null && (_user!.isLocked || _user!.isActivelySuspended)) {
        _suspensionExpiry = _user!.strikeExpiresAt;
        await _authService.signOut();
        _user = null;
        _error = 'account_suspended';
        _isLoading = false;
        _safeNotify();
        return false;
      }

      _isLoading = false;
      _safeNotify();
      return true;
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('email_not_confirmed') || raw.contains('Email not confirmed')) {
        _error = 'email_not_confirmed';
      } else if (raw.contains('banned') || raw.contains('User is banned')) {
        _error = 'account_suspended';
      } else if (raw.contains('SocketException') ||
          raw.contains('SocketFailed') ||
          raw.contains('ClientException') ||
          raw.contains('No address associated') ||
          raw.contains('Failed host lookup') ||
          raw.contains('errno = 7')) {
        _error = 'no_internet';
      } else {
        // Extract the human-readable message from AuthApiException wrappers
        final msgMatch =
            RegExp(r'message:\s*([^,)]+)').firstMatch(raw);
        _error = msgMatch?.group(1)?.trim() ??
            raw.replaceFirst('Exception: ', '');
      }
      _isLoading = false;
      _safeNotify();
      return false;
    }
  }

  // ── Sign Up (Resident) ────────────────────────────────────────────────
  Future<bool> signUp({
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
  }) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      await _authService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        barangayId: barangayId,
        address: address,
        dateOfBirth: dateOfBirth,
        guardianName: guardianName,
        guardianPhone: guardianPhone,
        guardianRelationship: guardianRelationship,
      );
      _user = await _authService.getCurrentProfile();
      _isLoading = false;
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      _safeNotify();
      return false;
    }
  }

  // Non-resident signup was removed 2026-08-08. Non-residents no longer hold
  // accounts at all — they use the passwordless one-time flow backed by
  // `non_resident_sessions`, which needs no registration and no approval.
  // Legacy `role = 'non_resident'` profiles still exist and can still sign in;
  // no new ones can be created.

  // ── Sign Out ────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    // Unsubscribe from FCM topics — fire-and-forget, must never block logout
    if (_user != null) {
      FcmService.instance.unsubscribeFromUser(_user!.id).catchError((_) {});
      if (_user!.isAdmin && _user!.barangayId != null) {
        FcmService.instance.unsubscribeFromBarangay(_user!.barangayId!).catchError((_) {});
      } else if (_user!.isSuperAdmin) {
        FcmService.instance.unsubscribeFromTopic('all_incidents').catchError((_) {});
      }
    }
    await _authService.signOut();
    _user = null;
    _error = null;
    _suspensionExpiry = null;
    _safeNotify();
  }

  // ── Reset Password ────────────────────────────────────────────────────
  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      await _authService.resetPassword(email);
      _isLoading = false;
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      _safeNotify();
      return false;
    }
  }

  // ── Update Profile ────────────────────────────────────────────────────
  Future<void> updateProfile(Map<String, dynamic> updates) async {
    if (_user == null) return;
    await _authService.updateProfile(_user!.id, updates);
    _user = await _authService.getProfile(_user!.id);
    _safeNotify();
  }

  // ── Refresh Profile ───────────────────────────────────────────────────
  Future<void> refreshProfile() async {
    if (_user == null) return;
    _user = await _authService.getProfile(_user!.id);
    _safeNotify();
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }

  // ── Disposal safety ───────────────────────────────────────────────────
  // Providers are torn down on logout and on navigation while their async
  // work is still in flight. `notifyListeners()` after `dispose()` throws
  // `A ChangeNotifier was used after being disposed` — an unhandled error on
  // a background future, which the user sees as a crash they cannot retry.
  bool _disposed = false;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
