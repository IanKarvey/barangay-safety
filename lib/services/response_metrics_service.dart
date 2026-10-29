import 'package:flutter/foundation.dart';

import '../models/response_metric.dart';
import '../utils/manila_time.dart';
import '../utils/response_export.dart';
import 'supabase_service.dart';

/// What the response-time page needs from the database. An interface so the
/// page can be tested with fixed data instead of a live connection.
abstract class ResponseDataSource {
  Future<({List<ResponseMetricRow> rows, bool truncated})> fetchRows({
    required DateTime from,
    required DateTime to,
  });

  Future<List<StatusLogRow>> fetchStatusLogs(List<String> reportIds);

  Future<List<EscalationEventRow>> fetchEscalations(List<String> reportIds);

  Future<void> logExport({
    required String userId,
    required String? userName,
    required String? barangayId,
    required String format,
    required ExportFilters filters,
    required int rowCount,
  });
}

/// Reads the response-time data and records exports.
///
/// Everything it reads is subject to the database's row-level rules: a barangay
/// admin gets their own barangay, the superadmin gets all, and nobody else gets
/// anything — the view runs with the caller's permissions (`security_invoker`).
class ResponseMetricsService implements ResponseDataSource {
  final _db = SupabaseService.instance;

  /// Rows fetched per request (Supabase returns at most 1000 by default).
  static const _page = 1000;

  /// Hard stop, so a very wide date range cannot freeze a browser tab. The
  /// dashboard says so when it is hit.
  static const maxRows = 10000;

  /// Reports submitted on or between the two PHILIPPINE calendar dates.
  /// Returns `(rows, truncated)` — `truncated` is true when [maxRows] was hit
  /// and there were more.
  @override
  Future<({List<ResponseMetricRow> rows, bool truncated})> fetchRows({
    required DateTime from,
    required DateTime to,
  }) async {
    final start = manilaDayStartUtc(from.year, from.month, from.day);
    final end = manilaDayStartUtc(to.year, to.month, to.day)
        .add(const Duration(days: 1));

    final out = <ResponseMetricRow>[];
    var offset = 0;
    var truncated = false;
    while (true) {
      final page = await _db.client
          .from('report_response_metrics')
          .select()
          .gte('submitted_at', start.toIso8601String())
          .lt('submitted_at', end.toIso8601String())
          .order('submitted_at', ascending: false)
          .range(offset, offset + _page - 1);

      for (final j in page) {
        try {
          out.add(ResponseMetricRow.fromJson(j));
        } catch (e) {
          debugPrint('ResponseMetricsService: skipping a bad row — $e');
        }
      }
      if (page.length < _page) break;
      offset += _page;
      if (offset >= maxRows) {
        truncated = true;
        break;
      }
    }
    return (rows: out, truncated: truncated);
  }

  @override
  Future<List<StatusLogRow>> fetchStatusLogs(List<String> reportIds) async {
    final out = <StatusLogRow>[];
    for (final chunk in _chunks(reportIds)) {
      final data = await _db.client
          .from('report_status_logs')
          .select()
          .inFilter('report_id', chunk)
          .order('changed_at');
      out.addAll(data.map(StatusLogRow.fromJson));
    }
    return out;
  }

  @override
  Future<List<EscalationEventRow>> fetchEscalations(
      List<String> reportIds) async {
    final out = <EscalationEventRow>[];
    for (final chunk in _chunks(reportIds)) {
      final data = await _db.client
          .from('report_escalation_events')
          .select()
          .inFilter('report_id', chunk)
          .order('triggered_at');
      out.addAll(data.map(EscalationEventRow.fromJson));
    }
    return out;
  }

  /// Records an export (who, when, which filters, how many rows).
  ///
  /// Throws if the record cannot be written — the caller must not hand over the
  /// file in that case. An export nobody can account for is worse than an
  /// export that has to be retried.
  @override
  Future<void> logExport({
    required String userId,
    required String? userName,
    required String? barangayId,
    required String format,
    required ExportFilters filters,
    required int rowCount,
  }) async {
    await _db.client.from('export_logs').insert({
      'user_id': userId,
      'user_name': userName,
      'barangay_id': barangayId,
      'format': format,
      'filters': filters.toJson(),
      'row_count': rowCount,
    });
  }

  /// Keeps each request URL short: a UUID is 36 characters, and a few hundred in
  /// one query string would be refused.
  static Iterable<List<String>> _chunks(List<String> ids, {int size = 60}) sync* {
    for (var i = 0; i < ids.length; i += size) {
      yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
    }
  }
}
