import 'package:flutter/foundation.dart';
import '../models/barangay_model.dart';
import '../services/barangay_service.dart';

class BarangayProvider with ChangeNotifier {
  final BarangayService _service = BarangayService();

  List<BarangayModel> _barangays = [];
  bool _isLoading = false;

  List<BarangayModel> get barangays => _barangays;
  bool get isLoading => _isLoading;

  Future<void> loadBarangays() async {
    if (_barangays.isNotEmpty) return;
    _isLoading = true;
    _safeNotify();

    try {
      _barangays = await _service.getBarangays();
    } catch (_) {
      // RLS may block unauthenticated access — use fallback
    }

    // Fallback: if Supabase query returned empty (RLS block), use hardcoded list
    if (_barangays.isEmpty) {
      _barangays = _fallbackBarangays();
    }

    _isLoading = false;
    _safeNotify();
  }

  BarangayModel? getById(String id) {
    try {
      return _barangays.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Hardcoded fallback for the 5 pilot barangays.
  /// Used when user is not yet authenticated (e.g. registration screen).
  List<BarangayModel> _fallbackBarangays() {
    final now = DateTime.now();
    return [
      BarangayModel(id: 'brgy-1', name: 'Barangay 1', centerLat: 13.9420, centerLng: 121.1640, createdAt: now),
      BarangayModel(id: 'brgy-2', name: 'Barangay 2', centerLat: 13.9435, centerLng: 121.1620, createdAt: now),
      BarangayModel(id: 'brgy-3', name: 'Barangay 3', centerLat: 13.9400, centerLng: 121.1610, createdAt: now),
      BarangayModel(id: 'brgy-7', name: 'Barangay 7', centerLat: 13.9390, centerLng: 121.1650, createdAt: now),
      BarangayModel(id: 'brgy-10', name: 'Barangay 10', centerLat: 13.9445, centerLng: 121.1660, createdAt: now),
    ];
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
