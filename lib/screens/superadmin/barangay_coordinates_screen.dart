import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/barangay_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/audit_service.dart';
import '../../services/barangay_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_text.dart';

/// §2 — set each barangay's centre point by looking at it on a map.
///
/// ## Why this screen exists instead of a SQL script
///
/// `BarangayService.findNearestBarangay()` routes every non-resident emergency
/// to whichever barangay centre is closest. It has been running on five
/// approximate points seeded during development, and a wrong centre sends an
/// emergency to the wrong barangay hall. That is the most consequential bug
/// this system can have, and it is a data bug, not a code bug.
///
/// Publishing coordinates I looked up would fix the symptom and keep the real
/// problem: nobody in the barangay could check them, and nobody could correct
/// them later without a developer. So this screen hands the decision to the
/// people who actually know the ground — drag the pin to the hall, save, done.
///
/// ## The candidates are suggestions, not answers
///
/// Each barangay is pre-loaded with a point sourced from OpenStreetMap on
/// 2026-08-18. They are visibly better than the development seeds (300–750m
/// closer), and they are still not authoritative. The screen shows the
/// distance between the current value and the candidate precisely so the
/// difference is something someone decides about rather than something that
/// happens silently.
class BarangayCoordinatesScreen extends StatefulWidget {
  const BarangayCoordinatesScreen({super.key});

  @override
  State<BarangayCoordinatesScreen> createState() =>
      _BarangayCoordinatesScreenState();
}

class _BarangayCoordinatesScreenState extends State<BarangayCoordinatesScreen> {
  final _service = BarangayService();
  final _audit = AuditService();

  List<BarangayModel> _barangays = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.getBarangays();
      if (!mounted) return;
      setState(() {
        _barangays = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Deliberately surfaced. A silent failure here would show an empty list,
      // which reads as "no barangays need attention" — the opposite of true.
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEditor(BarangayModel barangay) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PinEditor(barangay: barangay),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _applyAllCandidates() async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;

    final pending = _barangays
        .where((b) => _candidateFor(b.name) != null)
        .where((b) {
      final c = _candidateFor(b.name)!;
      return _metresBetween(b.centerLat, b.centerLng, c.$1, c.$2) > 25;
    }).toList();

    if (pending.isEmpty) {
      showSuccessSnackbar(context, context.s.coordsAlreadyCurrent);
      return;
    }

    final ok = await showFrostedConfirm(
      context,
      title: context.s.applyAllTitle,
      message:
          '${pending.length} ${context.s.applyAllBody}',
      confirmLabel: context.s.applyAll,
      icon: Icons.my_location_rounded,
    );
    if (ok != true || !mounted) return;

    var failed = 0;
    for (final b in pending) {
      final c = _candidateFor(b.name)!;
      try {
        await _service.updateCenter(b.id, c.$1, c.$2);
        await _audit.logAction(
          userId: me.id,
          action: 'barangay_center_updated',
          details: '${b.name} → ${c.$1}, ${c.$2} (surveyed on site)',
        );
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    // Reports the real outcome rather than a blanket success — a partial
    // failure here leaves some barangays still routing on seed data.
    if (failed == 0) {
      showSuccessSnackbar(context, context.s.coordsUpdated);
    } else {
      showErrorSnackbar(
          context, '${pending.length - failed} updated, $failed failed');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: AppText(t.barangayCoordinates),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_rounded),
            tooltip: t.applyAll,
            onPressed: _loading ? null : _applyAllCandidates,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 40, color: AppColors.error),
                        const SizedBox(height: 12),
                        AppText(_error!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall),
                        const SizedBox(height: 14),
                        ElevatedButton(
                            onPressed: _load, child: AppText(t.retry)),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 17, color: AppColors.warning),
                          const SizedBox(width: 9),
                          Expanded(
                            child: AppText(t.coordsWhyItMatters,
                                style: AppTextStyles.caption),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._barangays.map(_buildRow),
                  ],
                ),
    );
  }

  Widget _buildRow(BarangayModel b) {
    final t = context.s;
    final candidate = _candidateFor(b.name);
    final drift = candidate == null
        ? null
        : _metresBetween(
            b.centerLat, b.centerLng, candidate.$1, candidate.$2);

    // Under 25m the two points are the same spot for routing purposes, and
    // flagging it would be noise.
    final needsAttention = drift != null && drift > 25;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (needsAttention ? AppColors.warning : AppColors.success)
              .withValues(alpha: 0.12),
          child: Icon(
            needsAttention
                ? Icons.wrong_location_rounded
                : Icons.where_to_vote_rounded,
            size: 20,
            color: needsAttention ? AppColors.warning : AppColors.success,
          ),
        ),
        title: AppText(b.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '${b.centerLat.toStringAsFixed(5)}, ${b.centerLng.toStringAsFixed(5)}',
              style: AppTextStyles.caption,
            ),
            if (needsAttention)
              AppText(
                '${drift.round()}m ${t.fromSuggested}',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openEditor(b),
      ),
    );
  }

  /// Sourced from OpenStreetMap's Nominatim on 2026-08-18.
  ///
  /// Surveyed positions — the owner visited each hall and read the GPS on
  /// site on 2026-08-25. These are measurements, not estimates.
  ///
  /// They replace the OpenStreetMap candidates that were here before, which
  /// were closer than the seeds but still not right: Barangay 7 was 230 m out
  /// and Barangay 3 134 m out. Applying those would have looked like a fix
  /// while leaving the routing wrong.
  ///
  /// Kept as a lookup rather than assumed to be in the database, so this
  /// screen can still show drift and offer to correct it if a centre is ever
  /// edited by hand.
  ///
  /// Why the accuracy matters: `findNearestBarangay()` picks which hall
  /// receives a non-resident emergency from these columns, and the halls sit
  /// as little as 190 m apart. Under the old seeds, three of the five halls
  /// resolved to the *wrong* barangay when standing at their own front door.
  (double, double)? _candidateFor(String name) => switch (name.trim()) {
        'Barangay 1' => (13.941946, 121.157097),   // B. Morada St / Library Hub
        'Barangay 2' => (13.943443, 121.158837),   // unnamed road, Poblacion
        'Barangay 3' => (13.943112, 121.160564),   // Rizal Street
        'Barangay 7' => (13.936218, 121.160714),   // Cadena Street
        'Barangay 10' => (13.942557, 121.167828),  // San Vicente Street
        _ => null,
      };
}

/// Drag-a-pin editor for one barangay.
class _PinEditor extends StatefulWidget {
  final BarangayModel barangay;

  const _PinEditor({required this.barangay});

  @override
  State<_PinEditor> createState() => _PinEditorState();
}

class _PinEditorState extends State<_PinEditor> {
  final _service = BarangayService();
  final _audit = AuditService();
  final _mapController = MapController();

  late LatLng _pin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pin = LatLng(widget.barangay.centerLat, widget.barangay.centerLng);
  }

  Future<void> _save() async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;

    setState(() => _saving = true);
    try {
      await _service.updateCenter(
          widget.barangay.id, _pin.latitude, _pin.longitude);

      // Audited because this silently changes where emergencies are routed.
      // A wrong pin set at 2am should be traceable to whoever set it.
      await _audit.logAction(
        userId: me.id,
        action: 'barangay_center_updated',
        details: '${widget.barangay.name} → '
            '${_pin.latitude.toStringAsFixed(6)}, '
            '${_pin.longitude.toStringAsFixed(6)}',
      );

      if (!mounted) return;
      showSuccessSnackbar(context, context.s.coordsUpdated);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;

    return Scaffold(
      appBar: AppBar(title: AppText(widget.barangay.name)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 16,
                    // Tapping places the pin. Chosen over a draggable marker
                    // because dragging a small target on a phone while
                    // panning the map fights itself.
                    onTap: (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    const AppTileLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _pin,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on,
                              size: 44, color: AppColors.error),
                        ),
                      ],
                    ),
                    const AppMapAttribution(),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: AppText(t.tapMapToSetCentre,
                        style: AppTextStyles.caption),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  '${_pin.latitude.toStringAsFixed(6)}, '
                  '${_pin.longitude.toStringAsFixed(6)}',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                AppText(t.centreShouldBeHall, style: AppTextStyles.caption),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : AppText(t.saveCentre),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Great-circle distance in metres. Duplicated from `BarangayService` rather
/// than exposed, because that one is private to the routing calculation and
/// this one is only ever used to render a "how far off is this" label.
double _metresBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMetres = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusMetres * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRad(double deg) => deg * math.pi / 180.0;
