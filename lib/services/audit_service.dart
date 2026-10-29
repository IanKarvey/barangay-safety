import 'supabase_service.dart';
import '../models/audit_log_model.dart';

class AuditService {
  final _supabase = SupabaseService.instance;

  /// Log an action performed by an official.
  Future<void> logAction({
    required String userId,
    required String action,
    String? incidentId,
    String? details,
  }) async {
    await _supabase.client.from('audit_logs').insert({
      'user_id': userId,
      'action': action,
      'incident_id': incidentId,
      'details': details,
    });
  }

  /// Get audit logs for a specific incident.
  Future<List<AuditLogModel>> getIncidentLogs(String incidentId) async {
    final data = await _supabase.client
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .eq('incident_id', incidentId)
        .order('created_at', ascending: false)
        // Bounded. Every status change, assignment, dispatch and strike writes
        // a row here, so a long-running case accumulates them — and the panel
        // only ever renders the recent ones.
        .limit(100);

    return (data as List).map((json) => AuditLogModel.fromJson(json)).toList();
  }

  /// Get audit logs by user.
  Future<List<AuditLogModel>> getUserLogs(String userId) async {
    final data = await _supabase.client
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);

    return (data as List).map((json) => AuditLogModel.fromJson(json)).toList();
  }

  /// Get all audit logs (superadmin).
  Future<List<AuditLogModel>> getAllLogs({int limit = 100}) async {
    final data = await _supabase.client
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List).map((json) => AuditLogModel.fromJson(json)).toList();
  }
}
