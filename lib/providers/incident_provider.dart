import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/incident_model.dart';
import '../services/incident_service.dart';
import '../services/audit_service.dart';
import '../services/full_blast_service.dart';

class IncidentProvider with ChangeNotifier {
  final IncidentService _incidentService = IncidentService();
  final AuditService _auditService = AuditService();

  List<IncidentModel> _incidents = [];
  List<IncidentModel> _myIncidents = [];
  IncidentModel? _selectedIncident;
  Map<String, int> _stats = {};
  bool _isLoading = false;
  bool _myIncidentsLoading = false;
  String? _error;

  // Filters
  String? _statusFilter;
  int? _severityFilter;

  // Real-time
  StreamSubscription? _realtimeSubscription;

  /// Backs off before reconnecting a dropped realtime stream.
  Timer? _resubscribeTimer;

  /// Collapses a burst of realtime events into one refetch. See
  /// [_scheduleRealtimeRefresh].
  Timer? _refreshDebounce;

  bool _disposed = false;

  /// Notifies listeners unless this provider is already gone.
  ///
  /// Every method here is async, and the provider is torn down on logout while
  /// requests are still in flight. Calling `notifyListeners()` after `dispose()`
  /// throws `A ChangeNotifier was used after being disposed`, which is a red
  /// screen on a background task the user cannot see or retry — the reported
  /// "grey screen after logging out" had this shape.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<IncidentModel> get incidents => _incidents;
  List<IncidentModel> get myIncidents => _myIncidents;
  IncidentModel? get selectedIncident => _selectedIncident;
  Map<String, int> get stats => _stats;
  bool get isLoading => _isLoading;
  bool get myIncidentsLoading => _myIncidentsLoading;
  String? get error => _error;
  String? get statusFilter => _statusFilter;
  int? get severityFilter => _severityFilter;

  // ── Create Incident ───────────────────────────────────────────────────
  Future<IncidentModel?> createIncident({
    required String reporterId,
    required String barangayId,
    required String category,
    required String description,
    required int severityLevel,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    List<File> photos = const [],
    List<File> videos = const [],
    bool reportedViaVpn = false,
    bool locationMocked = false,
  }) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final incident = await _incidentService.createIncident(
        reporterId: reporterId,
        barangayId: barangayId,
        category: category,
        description: description,
        severityLevel: severityLevel,
        latitude: latitude,
        longitude: longitude,
        address: address,
        landmark: landmark,
        photos: photos,
        videos: videos,
        reportedViaVpn: reportedViaVpn,
        locationMocked: locationMocked,
      );

      // §14 — a critical report alerts the whole hall immediately rather than
      // waiting for someone to open the app. Deliberately not awaited into the
      // return value: the report is already saved, and a failed alert must
      // never present itself as a failed report.
      unawaited(FullBlastService().raiseForNewIncident(incident));

      _myIncidents.insert(0, incident);
      _incidents.insert(0, incident);
      _isLoading = false;
      _safeNotify();
      return incident;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      _safeNotify();
      return null;
    }
  }

  // ── Load Incidents for a Barangay (admin) ─────────────────────────────
  /// Loads the barangay queue.
  ///
  /// [silent] skips the loading flag. A realtime refresh is a background
  /// update of a list the official is already reading — flipping `_isLoading`
  /// replaced the whole queue with a spinner every time any row changed, so
  /// the list flickered and scroll position jumped while they were working.
  Future<void> loadBarangayIncidents(
    String barangayId, {
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      _safeNotify();
    }
    _error = null;

    try {
      _incidents = await _incidentService.getIncidentsByBarangay(
        barangayId,
        statusFilter: _statusFilter,
        severityFilter: _severityFilter,
      );
      _isLoading = false;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── Load All Incidents (superadmin) ───────────────────────────────────
  Future<void> loadAllIncidents({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _safeNotify();
    }
    _error = null;

    try {
      _incidents = await _incidentService.getAllIncidents(
        statusFilter: _statusFilter,
        severityFilter: _severityFilter,
      );
      _isLoading = false;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── Load My Incidents (resident) ──────────────────────────────────────
  Future<void> loadMyIncidents(String reporterId, {bool silent = false}) async {
    if (!silent) {
      _myIncidentsLoading = true;
      _safeNotify();
    }
    _error = null;

    try {
      _myIncidents = await _incidentService.getMyIncidents(reporterId);
      _myIncidentsLoading = false;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _myIncidentsLoading = false;
      _safeNotify();
    }
  }

  // ── Load Single Incident ──────────────────────────────────────────────
  Future<void> loadIncident(String incidentId, {bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _safeNotify();
    }

    try {
      _selectedIncident = await _incidentService.getIncident(incidentId);
      _isLoading = false;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── Update Status ─────────────────────────────────────────────────────
  Future<bool> updateStatus(
    String incidentId,
    String newStatus, {
    required String officialId,
    String? resolutionNotes,
    String? assignedTo,
  }) async {
    try {
      await _incidentService.updateIncidentStatus(
        incidentId,
        newStatus,
        resolutionNotes: resolutionNotes,
        assignedTo: assignedTo,
      );

      // Log the action
      await _auditService.logAction(
        userId: officialId,
        action: 'status_update',
        incidentId: incidentId,
        details: 'Status changed to $newStatus',
      );

      // Update local list
      _updateLocalIncident(incidentId, (i) => i.copyWith(status: newStatus));
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  /// §6 — "still active": silences the stale-case prompt for another window.
  ///
  /// Audited, because the point of the safety net is a trustworthy record. If
  /// a case is confirmed active four days running and still never resolved,
  /// the audit log is what shows that.
  Future<bool> confirmStillActive(
    String incidentId, {
    required String officialId,
  }) async {
    try {
      await _incidentService.touchIncident(incidentId);
      await _auditService.logAction(
        userId: officialId,
        action: 'still_active_confirmed',
        incidentId: incidentId,
        details: 'Official confirmed this case is still active',
      );
      // copyWith() already stamps updatedAt with now, which is exactly and
      // only what this action changes.
      _updateLocalIncident(incidentId, (i) => i.copyWith());
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  // ── Update Severity ───────────────────────────────────────────────────
  Future<bool> updateSeverity(
    String incidentId,
    int newLevel, {
    required String officialId,
  }) async {
    try {
      await _incidentService.updateSeverityLevel(incidentId, newLevel);

      await _auditService.logAction(
        userId: officialId,
        action: 'severity_change',
        incidentId: incidentId,
        details: 'Severity changed to Level $newLevel',
      );

      _updateLocalIncident(incidentId, (i) => i.copyWith(severityLevel: newLevel));
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  // ── Load Stats ────────────────────────────────────────────────────────
  Future<void> loadStats(String? barangayId) async {
    try {
      if (barangayId != null) {
        _stats = await _incidentService.getIncidentStats(barangayId);
      } else {
        _stats = await _incidentService.getAllIncidentStats();
      }
      _safeNotify();
    } catch (e) {
      _error = e.toString();
    }
  }

  // ── Filters ───────────────────────────────────────────────────────────
  void setStatusFilter(String? status) {
    _statusFilter = status;
    _safeNotify();
  }

  void setSeverityFilter(int? severity) {
    _severityFilter = severity;
    _safeNotify();
  }

  void clearFilters() {
    _statusFilter = null;
    _severityFilter = null;
    _safeNotify();
  }

  // ── Helper ────────────────────────────────────────────────────────────
  void _updateLocalIncident(
    String id,
    IncidentModel Function(IncidentModel) updater,
  ) {
    final idx = _incidents.indexWhere((i) => i.id == id);
    if (idx != -1) _incidents[idx] = updater(_incidents[idx]);

    final myIdx = _myIncidents.indexWhere((i) => i.id == id);
    if (myIdx != -1) _myIncidents[myIdx] = updater(_myIncidents[myIdx]);

    if (_selectedIncident?.id == id) {
      _selectedIncident = updater(_selectedIncident!);
    }
  }

  // ── Assign Incident ───────────────────────────────────────────────────
  Future<bool> assignIncident(
    String incidentId,
    String? assignedToId,
    String? assignedToName, {
    required String officialId,
  }) async {
    try {
      await _incidentService.assignIncident(incidentId, assignedToId);
      await _auditService.logAction(
        userId: officialId,
        action: 'assign',
        incidentId: incidentId,
        details: assignedToId == null
            ? 'Assignment removed'
            : 'Assigned to $assignedToName',
      );
      _updateLocalIncident(
        incidentId,
        (i) => i.copyWith(
          assignedTo: assignedToId,
          assignedToName: assignedToName,
        ),
      );
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  // ── Delete Incident (resident: own reports only) ──────────────────────
  Future<bool> deleteIncident(String incidentId) async {
    try {
      await _incidentService.deleteIncident(incidentId);
      _myIncidents.removeWhere((i) => i.id == incidentId);
      _incidents.removeWhere((i) => i.id == incidentId);
      if (_selectedIncident?.id == incidentId) _selectedIncident = null;
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _safeNotify();
      return false;
    }
  }

  // ── Real-Time: Subscribe (barangay officials) ─────────────────────────
  void subscribeToBarangay(String barangayId) {
    _cancelSubscription();
    _realtimeSubscription = _incidentService
        .subscribeToIncidents(barangayId)
        .listen(
      (_) {
        // Stats as well as the list — otherwise the dashboard counters drift
        // out of step with the incidents actually shown.
        _scheduleRealtimeRefresh(() async {
          await loadBarangayIncidents(barangayId, silent: true);
          await loadStats(barangayId);
        });
      },
      onError: (e) {
        // Without this the stream dies silently on the first error and never
        // recovers, so new reports stop appearing until the user logs out and
        // back in (which re-subscribes). That was exactly the reported symptom.
        debugPrint('IncidentProvider: realtime error, resubscribing: $e');
        _scheduleResubscribe(() => subscribeToBarangay(barangayId));
      },
      onDone: () {
        debugPrint('IncidentProvider: realtime closed, resubscribing');
        _scheduleResubscribe(() => subscribeToBarangay(barangayId));
      },
      cancelOnError: false,
    );
  }

  /// Coalesces a burst of realtime events into a single refetch.
  ///
  /// Supabase emits one event per changed row. A full-blast alert, a bulk
  /// status change, or simply three reports arriving together therefore fired
  /// the refresh three times — and each refresh was *two* full queries, one of
  /// which used to download every incident row in the barangay. On a hall
  /// laptop with a busy evening that was a self-inflicted denial of service.
  ///
  /// 400ms is below the threshold where a dispatcher would notice a delay, and
  /// comfortably above the gap between rows in a burst.
  void _scheduleRealtimeRefresh(Future<void> Function() refresh) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) return;
      refresh();
    });
  }

  /// Reconnects after a dropped realtime stream, with a short delay so a
  /// persistent failure doesn't become a tight reconnect loop.
  void _scheduleResubscribe(void Function() resubscribe) {
    _resubscribeTimer?.cancel();
    _resubscribeTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      resubscribe();
    });
  }

  // ── Real-Time: Subscribe (resident — their own reports) ───────────────
  /// Keeps a resident's own reports live.
  ///
  /// Without this the reporter's screens only ever updated when they tapped a
  /// push notification, because that navigates and triggers a fetch. An
  /// official could verify, dispatch and resolve a report and the person who
  /// filed it would see none of it — and pressing back returned them to a list
  /// still showing the old status.
  ///
  /// Refreshes the open incident as well as the list, so the detail screen
  /// updates under the reporter rather than only the row behind it.
  void subscribeToMyIncidents(String reporterId) {
    _cancelSubscription();
    _realtimeSubscription =
        _incidentService.subscribeToMyIncidents(reporterId).listen(
      (_) {
        _scheduleRealtimeRefresh(() async {
          await loadMyIncidents(reporterId, silent: true);
          final open = _selectedIncident;
          if (open != null) await loadIncident(open.id, silent: true);
        });
      },
      onError: (e) {
        debugPrint('IncidentProvider: realtime error, resubscribing: $e');
        _scheduleResubscribe(() => subscribeToMyIncidents(reporterId));
      },
      onDone: () {
        debugPrint('IncidentProvider: realtime closed, resubscribing');
        _scheduleResubscribe(() => subscribeToMyIncidents(reporterId));
      },
      cancelOnError: false,
    );
  }

  // ── Real-Time: Subscribe (superadmin — all barangays) ─────────────────
  void subscribeToAll() {
    _cancelSubscription();
    _realtimeSubscription = _incidentService.subscribeToAllIncidents().listen(
      (_) {
        _scheduleRealtimeRefresh(() async {
          await loadAllIncidents(silent: true);
          await loadStats(null);
        });
      },
      onError: (e) {
        debugPrint('IncidentProvider: realtime error, resubscribing: $e');
        _scheduleResubscribe(subscribeToAll);
      },
      onDone: () {
        debugPrint('IncidentProvider: realtime closed, resubscribing');
        _scheduleResubscribe(subscribeToAll);
      },
      cancelOnError: false,
    );
  }

  // ── Real-Time: Cancel subscription ────────────────────────────────────
  void _cancelSubscription() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscription();
    super.dispose();
  }

  void resetForLogout() {
    _cancelSubscription();
    _myIncidents = [];
    _incidents = [];
    _selectedIncident = null;
    _stats = {};
    _isLoading = false;
    _myIncidentsLoading = false;
    _error = null;
    _safeNotify();
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }
}
