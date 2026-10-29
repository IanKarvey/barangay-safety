import '../utils/severity.dart';
/// A single anonymised incident location for the heat map.
///
/// Deliberately NOT [IncidentModel]: this data is visible to residents, so it
/// must never carry a reporter, description, address or media. It mirrors
/// exactly what the `get_incident_heat_points` RPC returns, and coordinates
/// arrive already rounded (~100m) server-side so a density map cannot
/// pinpoint a specific home.
class HeatIncident {
  final double lat;
  final double lng;
  final int severityLevel;
  final String category;
  final DateTime createdAt;

  const HeatIncident({
    required this.lat,
    required this.lng,
    required this.severityLevel,
    required this.category,
    required this.createdAt,
  });

  factory HeatIncident.fromJson(Map<String, dynamic> json) {
    return HeatIncident(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      severityLevel:
          (json['severity_level'] as num?)?.toInt() ?? Severity.fallback,
      category: json['category'] as String? ?? 'Other',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Relative influence on the heat surface. Severity-weighted so one critical
  /// incident reads hotter than one noise complaint — a plain count would make
  /// the noisiest street look like the most dangerous one.
  double get weight => switch (severityLevel) {
        1 => 1.0,
        2 => 0.75,
        3 => 0.5,
        _ => 0.3,
      };
}
