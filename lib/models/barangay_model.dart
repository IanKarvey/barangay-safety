class BarangayModel {
  final String id;
  final String name;
  final double centerLat;
  final double centerLng;
  final String? description;
  final int? population;
  final DateTime createdAt;

  BarangayModel({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    this.description,
    this.population,
    required this.createdAt,
  });

  factory BarangayModel.fromJson(Map<String, dynamic> json) {
    return BarangayModel(
      id: json['id'] as String,
      name: json['name'] as String,
      centerLat: (json['center_lat'] as num).toDouble(),
      centerLng: (json['center_lng'] as num).toDouble(),
      description: json['description'] as String?,
      population: json['population'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'description': description,
      'population': population,
    };
  }
}
