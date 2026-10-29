import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../models/user_model.dart';

/// A barangay official currently sharing their position.
///
/// Deliberately a separate, narrow type rather than [UserModel]: this data is
/// readable by anonymous reporters, so it must never carry email, phone or ID
/// photo. It is backed by the `responder_locations` view, which exposes only
/// these columns.
class ResponderLocation {
  final String id;
  final String fullName;
  final String? position;

  /// Permission tier — used only to decide scope. A superadmin oversees the
  /// whole city, so scoping them to one barangay would hide them from
  /// reporters they are in fact responsible for.
  final String? role;

  final String? barangayId;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  const ResponderLocation({
    required this.id,
    required this.fullName,
    this.position,
    this.role,
    this.barangayId,
    required this.lat,
    required this.lng,
    this.updatedAt,
  });

  factory ResponderLocation.fromJson(Map<String, dynamic> json) {
    return ResponderLocation(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? 'Barangay Official',
      position: json['position'] as String?,
      role: json['role'] as String?,
      barangayId: json['barangay_id'] as String?,
      lat: (json['last_lat'] as num).toDouble(),
      lng: (json['last_lng'] as num).toDouble(),
      updatedAt: json['last_location_at'] != null
          ? DateTime.parse(json['last_location_at'] as String)
          : null,
    );
  }

  /// True when this responder answers city-wide rather than to one barangay.
  bool get isCityWide => role == 'superadmin';

  /// True when this position is too old to be trusted as "where they are now".
  bool staleAfter(Duration threshold) {
    if (updatedAt == null) return true;
    return DateTime.now().difference(updatedAt!) > threshold;
  }
}

/// Publishes and reads barangay officials' live positions.
///
/// Sharing is **opt-in and session-scoped** — see `is_sharing_location`. An
/// official is never tracked merely for being logged in; nothing is written
/// until they turn it on, and [stopSharing] clears the coordinates outright
/// rather than just flipping the flag.
class ResponderLocationService {
  final _supabase = SupabaseService.instance;

  /// Turn broadcasting on and publish the first fix.
  Future<void> startSharing(String userId, double lat, double lng) async {
    await _supabase.client.from('profiles').update({
      'is_sharing_location': true,
      'last_lat': lat,
      'last_lng': lng,
      'last_location_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Push a new fix. No-op server-side if the official isn't sharing, because
  /// the `responder_locations` view filters on `is_sharing_location`.
  Future<void> updateLocation(String userId, double lat, double lng) async {
    await _supabase.client.from('profiles').update({
      'last_lat': lat,
      'last_lng': lng,
      'last_location_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Stop broadcasting and erase the last known position.
  ///
  /// Clearing the coordinates matters: leaving a stale pin behind would let a
  /// reporter believe help is nearby when nobody is sharing at all.
  Future<void> stopSharing(String userId) async {
    await _supabase.client.from('profiles').update({
      'is_sharing_location': false,
      'last_lat': null,
      'last_lng': null,
      'last_location_at': null,
    }).eq('id', userId);
  }

  /// Responders visible to someone in [barangayId]. Null = everyone.
  ///
  /// Superadmins are always included regardless of barangay: they oversee the
  /// whole city, and filtering them out left a reporter seeing nobody while a
  /// city administrator was actively sharing their position.
  ///
  /// The filter is applied client-side rather than in the query because it is
  /// a two-branch rule (own barangay OR city-wide) — expressing that as a
  /// PostgREST `or=` string is far less readable than this, and the responder
  /// set is tiny.
  Future<List<ResponderLocation>> getResponders(String? barangayId) async {
    // Deliberately NOT caught: a failure here previously looked identical to
    // "no responders", which is exactly what made this bug invisible. Callers
    // decide how to surface it.
    final data = await _supabase.client.from('responder_locations').select();

    final responders = <ResponderLocation>[];
    for (final row in data as List) {
      try {
        final r = ResponderLocation.fromJson(row as Map<String, dynamic>);
        if (barangayId == null ||
            r.isCityWide ||
            r.barangayId == barangayId) {
          responders.add(r);
        }
      } catch (e) {
        debugPrint('ResponderLocationService: bad responder row: $e');
      }
    }
    return responders;
  }

  /// Live stream of responders in a barangay.
  ///
  /// Streams `profiles` rather than the view because Supabase realtime
  /// publishes tables, not views. The `is_sharing_location` filter is applied
  /// client-side here, and the sensitive columns are dropped in [fromJson] —
  /// officials reading this already have profile access, and reporters use
  /// [getResponders] against the view instead.
  Stream<List<ResponderLocation>> watchResponders(String barangayId) {
    return _supabase.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('barangay_id', barangayId)
        .map((rows) {
      final responders = <ResponderLocation>[];
      for (final row in rows) {
        if (row['is_sharing_location'] != true) continue;
        if (row['last_lat'] == null || row['last_lng'] == null) continue;
        try {
          responders.add(ResponderLocation.fromJson(row));
        } catch (e) {
          debugPrint('ResponderLocationService: bad stream row: $e');
        }
      }
      return responders;
    });
  }
}
