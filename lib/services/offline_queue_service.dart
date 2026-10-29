import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kQueueKey = 'offline_report_queue';

class QueuedReport {
  final String localId;
  final String reporterId;
  final String barangayId;
  final String category;
  final String description;
  final int severityLevel;
  final double latitude;
  final double longitude;
  final String? address;
  final String? landmark;
  final List<String> photoPaths;  // local file paths
  final List<String> videoPaths;
  final DateTime createdAt;

  QueuedReport({
    required this.localId,
    required this.reporterId,
    required this.barangayId,
    required this.category,
    required this.description,
    required this.severityLevel,
    required this.latitude,
    required this.longitude,
    this.address,
    this.landmark,
    this.photoPaths = const [],
    this.videoPaths = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'reporterId': reporterId,
        'barangayId': barangayId,
        'category': category,
        'description': description,
        'severityLevel': severityLevel,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'landmark': landmark,
        'photoPaths': photoPaths,
        'videoPaths': videoPaths,
        'createdAt': createdAt.toIso8601String(),
      };

  factory QueuedReport.fromJson(Map<String, dynamic> json) => QueuedReport(
        localId: json['localId'] as String,
        reporterId: json['reporterId'] as String,
        barangayId: json['barangayId'] as String,
        category: json['category'] as String,
        description: json['description'] as String,
        severityLevel: json['severityLevel'] as int,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
        landmark: json['landmark'] as String?,
        photoPaths: List<String>.from(json['photoPaths'] ?? []),
        videoPaths: List<String>.from(json['videoPaths'] ?? []),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class OfflineQueueService {
  Future<List<QueuedReport>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueueKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((j) => QueuedReport.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> enqueue(QueuedReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await getQueue();
    queue.add(report);
    await prefs.setString(_kQueueKey, jsonEncode(queue.map((r) => r.toJson()).toList()));
  }

  Future<void> remove(String localId) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await getQueue();
    queue.removeWhere((r) => r.localId == localId);
    await prefs.setString(_kQueueKey, jsonEncode(queue.map((r) => r.toJson()).toList()));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueueKey);
  }
}
