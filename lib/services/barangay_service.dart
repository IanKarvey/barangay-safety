import 'dart:math' as math;
import 'supabase_service.dart';
import '../models/barangay_model.dart';

class BarangayService {
  final _supabase = SupabaseService.instance;

  /// Find the barangay whose center is closest to the given point.
  ///
  /// Reads `center_lat`/`center_lng` straight from the `barangays` table, so
  /// this becomes accurate the moment real surveyed coordinates replace the
  /// current approximate seed values — no code change needed.
  ///
  /// Returns null if no barangay is within [maxDistanceKm] (default 20km,
  /// matching the Lipa City geofence) or if the table is empty.
  ///
  /// NOTE: center-point proximity is an approximation. Barangays are polygons,
  /// not circles — a point can be closer to a neighbour's center while still
  /// physically inside this barangay. Boundary polygons + point-in-polygon
  /// would be exact; see §2 in BARANGAY_CONNECT_REQUIREMENTS.md.
  Future<BarangayModel?> findNearestBarangay(
    double lat,
    double lng, {
    double maxDistanceKm = 20.0,
  }) async {
    final barangays = await getBarangays();
    if (barangays.isEmpty) return null;

    BarangayModel? nearest;
    double nearestKm = double.infinity;

    for (final b in barangays) {
      final km = _haversineKm(lat, lng, b.centerLat, b.centerLng);
      if (km < nearestKm) {
        nearestKm = km;
        nearest = b;
      }
    }

    return nearestKm <= maxDistanceKm ? nearest : null;
  }

  /// Great-circle distance in kilometres.
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  /// §2 — moves a barangay's routing centre.
  ///
  /// This is the single most consequential write in the app: every
  /// non-resident emergency is routed by comparing distance to these points,
  /// so a bad value here sends someone's emergency to the wrong barangay hall.
  /// The caller audits it for exactly that reason.
  Future<void> updateCenter(String barangayId, double lat, double lng) async {
    await _supabase.client.from('barangays').update({
      'center_lat': lat,
      'center_lng': lng,
    }).eq('id', barangayId);
  }

  /// Fetch all pilot barangays.
  Future<List<BarangayModel>> getBarangays() async {
    final data = await _supabase.client
        .from('barangays')
        .select()
        .order('name');

    return (data as List).map((json) => BarangayModel.fromJson(json)).toList();
  }

  /// Fetch a single barangay.
  Future<BarangayModel> getBarangay(String id) async {
    final data = await _supabase.client
        .from('barangays')
        .select()
        .eq('id', id)
        .single();

    return BarangayModel.fromJson(data);
  }
}
