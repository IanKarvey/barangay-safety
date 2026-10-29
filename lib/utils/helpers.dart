import 'dart:math' show pi, sin, cos, sqrt, atan2;
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import '../models/incident_model.dart';
import '../models/user_model.dart';
import 'escalation_clock.dart';
import 'severity.dart';
import '../widgets/app_text.dart';

// ── Geofencing ──────────────────────────────────────────────────────────────

const _lipaCityLat = 13.9411;
const _lipaCityLng = 121.1632;
const _lipaCityRadiusKm = 20.0;

double _deg2rad(double deg) => deg * pi / 180;

double lipaCityDistanceKm(double lat, double lng) {
  const R = 6371.0;
  final dLat = _deg2rad(lat - _lipaCityLat);
  final dLng = _deg2rad(lng - _lipaCityLng);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(_lipaCityLat)) * cos(_deg2rad(lat)) *
          sin(dLng / 2) * sin(dLng / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}

bool isWithinLipaCity(double lat, double lng) =>
    lipaCityDistanceKm(lat, lng) <= _lipaCityRadiusKm;

// ── Severity Helpers ────────────────────────────────────────────────────────

// 4 is the worst — see lib/utils/severity.dart.
Color severityColor(int level) {
  switch (level) {
    case Severity.critical:
      return AppColors.severityCritical;
    case Severity.high:
      return AppColors.severityHigh;
    case Severity.medium:
      return AppColors.severityMedium;
    case Severity.low:
      return AppColors.severityLow;
    default:
      return AppColors.textSecondary;
  }
}

String severityLabel(int level) {
  switch (level) {
    case Severity.critical:
      return 'CRITICAL';
    case Severity.high:
      return 'HIGH';
    case Severity.medium:
      return 'MEDIUM';
    case Severity.low:
      return 'LOW';
    default:
      return 'UNKNOWN';
  }
}

IconData severityIcon(int level) {
  switch (level) {
    case Severity.critical:
      return Icons.warning_rounded;
    case Severity.high:
      return Icons.error_rounded;
    case Severity.medium:
      return Icons.info_rounded;
    case Severity.low:
      return Icons.flag_rounded;
    default:
      return Icons.help_rounded;
  }
}

// ── Status Helpers ──────────────────────────────────────────────────────────

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return AppColors.statusPending;
    case 'in_progress':
      return AppColors.statusInProgress;
    case 'resolved':
      return AppColors.statusResolved;
    case 'flagged':
      return AppColors.statusFlagged;
    default:
      return AppColors.textSecondary;
  }
}

/// English status label. Used where text leaves this device — push
/// notification bodies are stored server-side and may be read by someone
/// whose language setting differs from the sender's.
String statusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return 'Pending';
    case 'verified':
      return 'Verified';
    case 'assigned':
      return 'Assigned';
    case 'responding':
    case 'in_progress':
      return 'Responding';
    case 'on_scene':
      return 'On Scene';
    case 'resolved':
      return 'Resolved';
    case 'flagged':
      return 'Flagged';
    default:
      return status;
  }
}

/// Localized status label for anything drawn on screen.
///
/// Covers all six stages — the English-only version above fell through to the
/// raw database value for the newer ones, so residents were shown `on_scene`.
String statusLabelFor(AppStrings t, String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return t.statusPending;
    case 'verified':
      return t.statusVerified;
    case 'assigned':
      return t.statusAssigned;
    case 'responding':
    case 'in_progress':
      return t.statusResponding;
    case 'on_scene':
      return t.statusOnScene;
    case 'resolved':
      return t.statusResolved;
    case 'flagged':
      return t.statusFlagged;
    default:
      return status;
  }
}

/// Human-readable distance. Metres below 1km so "220 m away" reads usefully
/// on foot, kilometres above that.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return km < 10
      ? '${km.toStringAsFixed(1)} km'
      : '${km.round()} km';
}

/// Job title for display. Prefers the barangay hall position when one is
/// assigned, otherwise falls back to the permission tier — legacy officials
/// created before positions existed have role but no position.
String userDisplayTitle(UserModel user) {
  if (user.position != null) return UserPosition.label(user.position);
  if (user.isSuperAdmin) return 'Administrator';
  if (user.isAdmin) return 'Barangay Official';
  if (user.isNonResident) return 'Non-Resident';
  return 'Resident';
}

/// Icon representing a barangay hall position.
IconData positionIcon(String? position) {
  switch (position) {
    case UserPosition.secretary:
      return Icons.assignment_ind_rounded;
    case UserPosition.captain:
      return Icons.stars_rounded;
    case UserPosition.tanod:
      return Icons.shield_rounded;
    case UserPosition.staff:
      return Icons.badge_rounded;
    default:
      return Icons.person_rounded;
  }
}

IconData statusIcon(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return Icons.schedule_rounded;
    case 'in_progress':
      return Icons.autorenew_rounded;
    case 'resolved':
      return Icons.check_circle_rounded;
    case 'flagged':
      return Icons.flag_rounded;
    default:
      return Icons.circle;
  }
}

// ── Date / Time ─────────────────────────────────────────────────────────────

String formatDateTime(DateTime dt) {
  return DateFormat('MMM dd, yyyy – hh:mm a').format(dt);
}

String formatDateOnly(DateTime dt) {
  return DateFormat('MMM dd, yyyy').format(dt);
}

String formatTimeOnly(DateTime dt) {
  return DateFormat('hh:mm a').format(dt);
}

String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDateOnly(dt);
}

// ── SLA / Response Time Helpers ─────────────────────────────────────────────

// How late a report is, as 'ok' / 'warning' / 'overdue'.
//
//   UNANSWERED (pending, nobody has acted):  5 min warning / 15 min overdue
//   being handled (verified, assigned, in_progress, responding, on_scene):
//                                             24h warning / 48h overdue
//
// The first line is the automatic escalation for a resident who may be waiting
// for rescue (tiers at 5 / 10 / 15 minutes, escalate_unanswered_reports in
// supabase/migration_2026_10_20_three_features.sql): 'warning' is tier 1 and
// 'overdue' is the last tier, "Unattended / Last Resort". The second is the
// slower check on a report someone has taken but not finished
// (escalate_overdue_incidents). The badge and the alert agree because both read
// the same lines; [step] is the 5 minutes, passed in so a demo run with a
// shorter interval still matches.
//
// The old 12h / 24h line for waiting reports is gone: it was far too slow for
// someone waiting for help.
//
// An action that is not a status change (a message to the resident) leaves a
// report 'pending' but answered, so it moves to the slower rule.
// [now] exists so the boundaries can be tested.
String slaStatus(
  IncidentModel incident, {
  DateTime? now,
  Duration step = kDefaultEscalationStep,
}) {
  if (incident.isResolved || incident.isFlagged || incident.status == 'closed') {
    return 'ok';
  }
  final age = (now ?? DateTime.now()).difference(incident.createdAt);

  if (incident.isUnanswered) {
    if (age >= step * 3) return 'overdue';
    if (age >= step) return 'warning';
    return 'ok';
  }

  final hours = age.inHours;
  if (hours >= 48) return 'overdue';
  if (hours >= 24) return 'warning';
  return 'ok';
}

Color slaColor(String status) {
  switch (status) {
    case 'overdue': return AppColors.error;
    case 'warning': return AppColors.warning;
    default: return AppColors.textTertiary;
  }
}

String slaElapsedLabel(IncidentModel incident) {
  final diff = DateTime.now().difference(incident.createdAt);
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  if (h == 0) return '${m}m elapsed';
  if (m == 0) return '${h}h elapsed';
  return '${h}h ${m}m elapsed';
}

// ── Snackbar Helpers ────────────────────────────────────────────────────────

void showSuccessSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: AppText(message)),
        ],
      ),
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 3),
    ),
  );
}

void showErrorSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: AppText(message)),
        ],
      ),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 4),
    ),
  );
}

void showInfoSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: AppText(message)),
        ],
      ),
      backgroundColor: AppColors.primary,
      duration: const Duration(seconds: 3),
    ),
  );
}

// ── Outside City Sheet ──────────────────────────────────────────────────────

/// Shows a bottom sheet that can always be dismissed.
///
/// `isScrollControlled: true` lets a sheet grow past half the screen, but a
/// bare `Column` inside one does not scroll — it overflows. On a short screen,
/// or with a large system font scale, the action button at the bottom is
/// pushed off the display, and because the sheet then covers everything there
/// is no barrier left to tap either. That is a sheet with no visible way out,
/// which is exactly what was reported for the outside-Lipa notice
/// (2026-09-15).
///
/// Capping the height and making the body scroll means the button is always
/// reachable, whatever the screen or font size.
Future<void> showOutsideCitySheet(BuildContext context, double distanceKm) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => SingleChildScrollView(
      child: _OutsideCitySheet(distanceKm: distanceKm),
    ),
  );
}

class _OutsideCitySheet extends StatelessWidget {
  final double distanceKm;
  const _OutsideCitySheet({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final distLabel = distanceKm >= 10
        ? '${distanceKm.toStringAsFixed(0)} km'
        : '${distanceKm.toStringAsFixed(1)} km';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wrong_location_rounded, size: 40, color: AppColors.error),
          )
              .animate()
              .scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.easeOutBack)
              .fadeIn(duration: 300.ms),
          const SizedBox(height: 20),
          const AppText(
            'Outside Lipa City',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary, letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          )
              .animate(delay: 80.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13.5,
                color: AppColors.textSecondary, height: 1.6,
              ),
              children: [
                const TextSpan(text: 'This app is exclusively for '),
                const TextSpan(
                  text: 'Lipa City, Batangas',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const TextSpan(text: ' residents.\n\nYour current location is '),
                TextSpan(
                  text: 'approximately $distLabel away',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.error),
                ),
                const TextSpan(text: ' from Lipa City.'),
              ],
            ),
          )
              .animate(delay: 140.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16,
                    color: AppColors.warning.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'For emergencies outside Lipa City, contact your local barangay officials or dial 911.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11.5,
                      color: AppColors.textSecondary, height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('I Understand'),
            ),
          )
              .animate(delay: 260.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
        ],
      ),
    ).animate().slideY(begin: 0.2, end: 0, duration: 420.ms, curve: Curves.easeOutBack);
  }
}

// ── Frosted Glass Confirm Sheet ─────────────────────────────────────────────

/// Replaces AlertDialog with a spring-animated bottom sheet.
/// Returns true (confirm) or false/null (cancel).
Future<bool?> showFrostedConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (ctx) => _FrostedConfirmSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
  );
}

class _FrostedConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  const _FrostedConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final confirmColor = destructive ? AppColors.error : AppColors.primary;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (icon != null) ...[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: confirmColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: confirmColor, size: 28),
            ),
            const SizedBox(height: 16),
          ],
          AppText(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          AppText(
            message,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: AppText(cancelLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: confirmColor),
                  onPressed: () => Navigator.pop(context, true),
                  child: AppText(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .slideY(
          begin: 0.18,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 280.ms);
  }
}

// ── Validation ──────────────────────────────────────────────────────────────

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Email is required';
  final regex = RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$');
  if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 6) return 'Password must be at least 6 characters';
  return null;
}

String? validateRequired(String? value, [String field = 'This field']) {
  if (value == null || value.trim().isEmpty) return '$field is required';
  return null;
}

String? validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) return 'Phone number is required';
  final cleaned = value.replaceAll(RegExp(r'[\s\-()]'), '');
  if (cleaned.length < 10 || cleaned.length > 13) {
    return 'Enter a valid phone number';
  }
  return null;
}

// ── Bulk work ───────────────────────────────────────────────────────────────

/// Runs [action] over [items] a few at a time, in order of completion.
///
/// Bulk actions in this app were written as `for (final id in ids) await ...`,
/// which is one full network round trip per item, one after the other. Marking
/// twenty reports resolved meant twenty status writes *and* twenty audit-log
/// writes end to end — long enough that officials assumed the app had frozen
/// and started tapping again.
///
/// Bounded rather than a plain `Future.wait`: firing fifty simultaneous writes
/// at Supabase risks rate limiting and gives a phone on barangay wifi more
/// sockets than it can usefully hold. Six is comfortably below both limits and
/// still turns a twenty-item batch from twenty sequential trips into four.
///
/// Never throws. Each result is reported independently so one failure in a
/// batch cannot discard the successes — the caller counts what worked and
/// tells the user honestly.
Future<List<bool>> runBulk<T>(
  List<T> items,
  Future<bool> Function(T item) action, {
  int concurrency = 6,
}) async {
  final results = List<bool>.filled(items.length, false);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      try {
        results[i] = await action(items[i]);
      } catch (_) {
        results[i] = false;
      }
    }
  }

  final lanes = concurrency < items.length ? concurrency : items.length;
  await Future.wait([for (var i = 0; i < lanes; i++) worker()]);
  return results;
}
