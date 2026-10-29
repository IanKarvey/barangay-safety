import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../l10n/response_strings.dart';
import '../services/emergency_contacts_service.dart';
import '../utils/constants.dart';

/// The "last resort" pop-up: the barangay is busy, here are the numbers to call.
///
/// Opened automatically when a report reaches tier 3 unanswered, and from the
/// "Call for help now" button on the waiting card afterwards. Every number is a
/// big tap-to-call button; the list is the barangay's own, else the city's, else
/// 911 (see [resolveEmergencyNumbers]).
Future<void> showEmergencyNumbers(
  BuildContext context, {
  required String barangayId,
  EmergencyContactsService? service,
}) {
  HapticFeedback.heavyImpact();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (_) => EmergencyNumbersDialog(
      barangayId: barangayId,
      service: service ?? EmergencyContactsService(),
    ),
  );
}

class EmergencyNumbersDialog extends StatefulWidget {
  const EmergencyNumbersDialog({
    super.key,
    required this.barangayId,
    required this.service,
    this.contacts,
  });

  final String barangayId;
  final EmergencyContactsService service;

  /// Preloaded list (tests). When null the dialog loads from [service].
  final List<EmergencyContact>? contacts;

  @override
  State<EmergencyNumbersDialog> createState() => _EmergencyNumbersDialogState();
}

class _EmergencyNumbersDialogState extends State<EmergencyNumbersDialog> {
  List<EmergencyContact>? _contacts;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _contacts = widget.contacts;
    if (_contacts == null) _load();
  }

  Future<void> _load() async {
    final list = await widget.service.numbersFor(widget.barangayId);
    if (mounted) setState(() => _contacts = list);
  }

  Future<void> _call(EmergencyContact c) async {
    HapticFeedback.mediumImpact();
    var launched = false;
    try {
      launched = await launchUrl(
        Uri(scheme: 'tel', path: c.dial),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;
    // No dialer (a tablet, an emulator): copy the number so it can still be
    // dialled by hand, and say so rather than doing nothing.
    await Clipboard.setData(ClipboardData(text: c.dial));
    if (mounted) setState(() => _notice = context.s.referralNoDialer);
  }

  static IconData _icon(String category) => switch (category) {
        'police' => Icons.local_police_rounded,
        'hospital' => Icons.medical_services_rounded,
        'rescue' => Icons.health_and_safety_rounded,
        'fire' => Icons.local_fire_department_rounded,
        _ => Icons.phone_in_talk_rounded,
      };

  static Color _color(String category) => switch (category) {
        'police' => const Color(0xFF1E40AF),
        'hospital' => const Color(0xFFBE123C),
        'rescue' => const Color(0xFF0E7490),
        'fire' => const Color(0xFFDC2626),
        _ => const Color(0xFF334155),
      };

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final contacts = _contacts;
    final builtIn = contacts != null && isBuiltInSet(contacts);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFF991B1B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_in_talk_rounded,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          rs.escalationTitle(3),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    rs.escalationMessage(3),
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (contacts == null)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Column(
                      children: [
                        for (final c in contacts) ...[
                          _CallButton(
                            contact: c,
                            icon: _icon(c.category),
                            color: _color(c.category),
                            hint: rs.tapToCall,
                            onTap: () => _call(c),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                if (builtIn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      rs.usingStandardNumbers,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _notice!,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(rs.close, style: const TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.contact,
    required this.icon,
    required this.color,
    required this.hint,
    required this.onTap,
  });

  final EmergencyContact contact;
  final IconData icon;
  final Color color;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${contact.label} ${contact.shown}',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          contact.shown,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.call_rounded, color: Colors.white, size: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
