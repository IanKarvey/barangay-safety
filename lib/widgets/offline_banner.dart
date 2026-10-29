import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    ConnectivityService.onStatusChange.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _checkInitial() async {
    final online = await ConnectivityService.isOnline();
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: _isOnline ? 0 : 44,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        color: _isOnline ? AppColors.success : AppColors.error,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            Icon(
              _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: Colors.white,
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _isOnline
                      ? 'Back online — submitting queued reports'
                      : 'You\'re offline — reports will be saved and submitted when back online',
                  key: ValueKey(_isOnline),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
