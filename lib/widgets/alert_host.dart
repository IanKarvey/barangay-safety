import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/response_strings.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../utils/alert_sound.dart';
import '../utils/constants.dart';
import '../utils/incident_route.dart';
import 'emergency_numbers_sheet.dart';

/// Turns the escalation notifications that arrive while the app is open into
/// pop-ups.
///
/// * An OFFICIAL gets a pop-up that stays until dismissed and plays an alert
///   sound on a loop (web: a tone; phone: vibration, with the sound coming from
///   the system notification) when a report goes unanswered.
/// * A RESIDENT gets the matching apology message at each tier, the
///   emergency-numbers pop-up at the last tier, and a "good news" message the
///   moment an official starts responding — including after the last tier.
///
/// Mounted once, above the Navigator (see `MaterialApp.builder`), so it works on
/// whatever screen the person happens to be on. It uses [navigatorKey] to show
/// dialogs because its own context is above the Navigator.
///
/// What it does not cover: a notification that arrived while the app was closed.
/// Those are still in the notification list, and a resident whose report reached
/// the last tier sees the emergency-numbers button on the report itself.
class AlertHost extends StatefulWidget {
  const AlertHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AlertHost> createState() => _AlertHostState();
}

class _AlertHostState extends State<AlertHost> {
  StreamSubscription<NotificationModel>? _sub;
  NotificationProvider? _provider;

  final List<NotificationModel> _officialQueue = [];
  bool _officialShowing = false;

  /// Anything older than this is history, not news. Generous because the
  /// notification's timestamp is the server's and the check uses the phone's.
  static const _freshFor = Duration(minutes: 30);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.read<NotificationProvider>();
    if (!identical(p, _provider)) {
      _sub?.cancel();
      _provider = p;
      _sub = p.arrivals.listen(_onArrival);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    AlertSound.stop();
    super.dispose();
  }

  BuildContext? get _navContext => widget.navigatorKey.currentContext;

  void _onArrival(NotificationModel n) {
    if (DateTime.now().difference(n.createdAt) > _freshFor) return;

    switch (n.type) {
      case 'escalation':
        if (n.data?['kind'] == 'unanswered') {
          _officialQueue.add(n);
          _pumpOfficial();
        }
      case 'escalation_resident':
        _showResidentEscalation(n);
      case 'responder_update':
        _showGoodNews(n);
    }
  }

  // ── Officials ────────────────────────────────────────────────────────────
  Future<void> _pumpOfficial() async {
    if (_officialShowing || _officialQueue.isEmpty) return;
    final ctx = _navContext;
    if (ctx == null) return;

    _officialShowing = true;
    final n = _officialQueue.removeAt(0);
    AlertSound.start();
    HapticFeedback.heavyImpact();

    final open = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => OfficialAlertDialog(notification: n),
    );

    _officialShowing = false;
    if (_officialQueue.isEmpty) AlertSound.stop();

    final id = n.incidentId;
    final nav = widget.navigatorKey.currentState;
    final navCtx = _navContext;
    if (open == true && id != null && nav != null && navCtx != null) {
      nav.pushNamed(incidentRouteForCurrentUser(navCtx), arguments: id);
    }
    _pumpOfficial();
  }

  // ── Residents ────────────────────────────────────────────────────────────
  Future<void> _showResidentEscalation(NotificationModel n) async {
    final ctx = _navContext;
    if (ctx == null) return;
    final level = (n.data?['level'] as num?)?.toInt() ?? 1;

    // A reminder ("still waiting") arrives every five minutes after the last
    // tier. The numbers pop-up already opened once and the report itself keeps
    // its "Call for help now" button; opening it again every five minutes would
    // be harassing someone who is frightened. The push and the notification list
    // still carry the reminder.
    if (n.data?['reminder'] != null) return;

    if (level >= 3) {
      final barangayId = ctx.read<AuthProvider>().user?.barangayId ?? '';
      await showEmergencyNumbers(ctx, barangayId: barangayId);
      return;
    }

    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) {
        final rs = dialogCtx.rs;
        return AlertDialog(
          icon: Icon(
            level == 1 ? Icons.hourglass_top_rounded : Icons.campaign_rounded,
            size: 44,
            color: level == 1 ? AppColors.warning : AppColors.error,
          ),
          title: Text(rs.escalationTitle(level), textAlign: TextAlign.center),
          content: Text(
            rs.escalationMessage(level),
            style: const TextStyle(fontSize: 17, height: 1.35),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(140, 50)),
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(rs.close, style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showGoodNews(NotificationModel n) async {
    final ctx = _navContext;
    if (ctx == null) return;
    final id = n.incidentId;

    final open = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) {
        final rs = dialogCtx.rs;
        final role = rs.roleLabel(n.data?['role'] as String?);
        final name = (n.data?['name'] as String?) ?? '';
        return AlertDialog(
          icon: const Icon(Icons.check_circle_rounded,
              size: 52, color: AppColors.success),
          title: Text(rs.helpOnTheWayTitle, textAlign: TextAlign.center),
          content: Text(
            rs.goodNews(role, name).replaceAll('  ', ' '),
            style: const TextStyle(fontSize: 17, height: 1.35),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(rs.close, style: const TextStyle(fontSize: 16)),
            ),
            if (id != null)
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(rs.viewReport, style: const TextStyle(fontSize: 16)),
              ),
          ],
        );
      },
    );

    final nav = widget.navigatorKey.currentState;
    final navCtx = _navContext;
    if (open == true && id != null && nav != null && navCtx != null) {
      nav.pushNamed(incidentRouteForCurrentUser(navCtx), arguments: id);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The pop-up an official sees when a report has gone unanswered.
///
/// Not dismissible by tapping outside: the point is that it cannot be missed.
class OfficialAlertDialog extends StatelessWidget {
  const OfficialAlertDialog({super.key, required this.notification});

  final NotificationModel notification;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final level = (notification.data?['level'] as num?)?.toInt() ?? 1;
    final last = level >= 3;
    final color = last
        ? const Color(0xFF991B1B)
        : level == 2
            ? const Color(0xFFEA580C)
            : const Color(0xFFD97706);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color, width: 3),
        ),
        icon: Icon(
          last ? Icons.crisis_alert_rounded : Icons.notifications_active_rounded,
          size: 48,
          color: color,
        ),
        title: Text(
          rs.alertTitle(level),
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            notification.body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(rs.dismiss),
          ),
          if (notification.incidentId != null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(rs.openReport),
            ),
        ],
      ),
    );
  }
}
