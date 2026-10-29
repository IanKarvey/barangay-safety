import 'package:flutter/material.dart';

import '../l10n/response_strings.dart';
import '../utils/constants.dart';

/// The picture for one tutorial step: a simplified screen of the app with the
/// one thing to press ringed in orange and a pointing hand on it.
///
/// Drawn from plain widgets instead of screenshots, so it never goes out of date
/// when the app's styling changes, is the same on every phone, and follows the
/// language setting. Everything in it is deliberately big and few: the point is
/// "look HERE", not a faithful copy of the app.
class TutorialIllustration extends StatelessWidget {
  const TutorialIllustration({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return ExcludeSemantics(
      // The words on screen carry the meaning; the picture is decoration. It is
      // also a PICTURE of a phone screen, so it must not grow with the phone's
      // font setting: scaled up, the little labels inside would overflow the
      // little screen they are drawn on. The real text around it still scales.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: _frame(rs),
      ),
    );
  }

  Widget _frame(ResponseStrings rs) => AspectRatio(
        aspectRatio: 1.1,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE8EEF7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.all(14),
          child: _PhoneFrame(child: _screenFor(step, rs)),
        ),
      );

  Widget _screenFor(int step, ResponseStrings rs) => switch (step) {
        0 => _HomeScreen(rs),
        1 => _CategoryScreen(rs),
        2 => _LocationScreen(rs),
        3 => _DescribeScreen(rs),
        4 => _SubmitScreen(rs),
        5 => _WaitingScreen(rs),
        _ => _StatusScreen(rs),
      };
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.62,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF1E293B), width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// A ringed, pulsing "press this" marker around [child].
class _Target extends StatefulWidget {
  const _Target({required this.child, this.radius = 14});
  final Widget child;
  final double radius;

  @override
  State<_Target> createState() => _TargetState();
}

class _TargetState extends State<_Target> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With the phone's reduce-motion setting on, the ring is still there — it
    // just does not pulse.
    final still = MediaQuery.of(context).disableAnimations;
    if (still && _c.isAnimating) _c.stop();

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = still ? 0.5 : _c.value;
        return Stack(
          // Passthrough: a ringed grid tile must still fill its grid cell.
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(color: const Color(0xFFF97316), width: 3.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF97316).withValues(alpha: 0.25 + 0.3 * t),
                    blurRadius: 6 + 10 * t,
                    spreadRadius: 1 + 3 * t,
                  ),
                ],
              ),
              child: child,
            ),
            Positioned(
              // Below and to the side of the ring, so the hand points at the
              // button without covering the words on it.
              right: 2,
              bottom: -30,
              child: Transform.translate(
                offset: Offset(0, -4 * t),
                child: const Icon(Icons.touch_app_rounded,
                    size: 38, color: Color(0xFF111827)),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.widthFactor, {this.height = 8, this.color = const Color(0xFFE2E8F0)});
  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: Container(
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
      );
}

Widget _gap(double h) => SizedBox(height: h);

Widget _header(Color color) => Container(
      height: 34,
      color: color,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: const _Bar(0.4, height: 7, color: Colors.white54),
    );

Widget _bigButton(String label, Color color, {IconData? icon, double height = 38}) =>
    Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

// ── 0: the home screen ──────────────────────────────────────────────────────
class _HomeScreen extends StatelessWidget {
  const _HomeScreen(this.rs);
  final ResponseStrings rs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _Target(
                    child: _bigButton(rs.mockReportButton, AppColors.primary,
                        icon: Icons.shield_rounded, height: 46),
                  ),
                  _gap(20),
                  Container(
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCEBDD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.map_rounded, color: Color(0xFF86B58B), size: 30),
                  ),
                  _gap(12),
                  const _Bar(0.9),
                  _gap(7),
                  const _Bar(0.6),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── 1: choose what happened ─────────────────────────────────────────────────
class _CategoryScreen extends StatelessWidget {
  const _CategoryScreen(this.rs);
  final ResponseStrings rs;

  Widget _tile(IconData icon, String label, Color color) => Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Target(child: _tile(Icons.local_fire_department_rounded, rs.mockFire, const Color(0xFFDC2626))),
                  _tile(Icons.lock_rounded, rs.mockTheft, const Color(0xFF7C3AED)),
                  _tile(Icons.directions_car_rounded, rs.mockAccident, const Color(0xFFEA580C)),
                  _tile(Icons.medical_services_rounded, rs.mockMedical, const Color(0xFF059669)),
                  _tile(Icons.volume_up_rounded, rs.mockNoise, const Color(0xFF0284C7)),
                  _tile(Icons.more_horiz_rounded, rs.mockOther, const Color(0xFF64748B)),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── 2: location ─────────────────────────────────────────────────────────────
class _LocationScreen extends StatelessWidget {
  const _LocationScreen(this.rs);
  final ResponseStrings rs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCEBDD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 44),
                      ),
                    ),
                  ),
                  _gap(12),
                  _Target(
                    child: _bigButton(rs.mockUseLocation, AppColors.primary,
                        icon: Icons.my_location_rounded),
                  ),
                  _gap(14),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── 3: describe ─────────────────────────────────────────────────────────────
class _DescribeScreen extends StatelessWidget {
  const _DescribeScreen(this.rs);
  final ResponseStrings rs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _Target(
                    child: Container(
                      height: 92,
                      width: double.infinity,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(rs.mockWriteHere,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  _gap(22),
                  Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_rounded, size: 17, color: Color(0xFF475569)),
                        const SizedBox(width: 6),
                        Text(rs.mockAddPhoto,
                            style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── 4: submit ───────────────────────────────────────────────────────────────
class _SubmitScreen extends StatelessWidget {
  const _SubmitScreen(this.rs);
  final ResponseStrings rs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const _Bar(0.5, height: 10, color: Color(0xFFCBD5E1)),
                  _gap(10),
                  const _Bar(0.95),
                  _gap(7),
                  const _Bar(0.8),
                  _gap(7),
                  const _Bar(0.65),
                  const Spacer(),
                  _Target(
                    child: _bigButton(rs.mockSubmit, const Color(0xFF16A34A),
                        icon: Icons.send_rounded, height: 46),
                  ),
                  _gap(16),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── 5: what happens next ────────────────────────────────────────────────────
class _WaitingScreen extends StatelessWidget {
  const _WaitingScreen(this.rs);
  final ResponseStrings rs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCA8A04), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: Color(0xFFCA8A04), size: 30),
                    _gap(6),
                    Text(rs.waitedLabel('3:42'),
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF92400E))),
                    _gap(8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.74,
                        minHeight: 7,
                        backgroundColor: Color(0xFFFDE68A),
                        valueColor: AlwaysStoppedAnimation(Color(0xFFCA8A04)),
                      ),
                    ),
                    const Spacer(),
                    _Target(
                      child: _bigButton(rs.callForHelpNow, const Color(0xFFDC2626),
                          icon: Icons.call_rounded),
                    ),
                    _gap(8),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

// ── 6: check status ─────────────────────────────────────────────────────────
class _StatusScreen extends StatelessWidget {
  const _StatusScreen(this.rs);
  final ResponseStrings rs;

  // Each item shrinks to fit its slot: "Mga Report Ko" is wider than "My Reports"
  // and the little tab bar has only so much room.
  Widget _navItem(IconData icon, String label, {bool active = false}) => Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: active ? AppColors.primary : const Color(0xFF94A3B8)),
              Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: active ? AppColors.primary : const Color(0xFF94A3B8))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _header(const Color(0xFF0D2272)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(rs.mockOnTheWay,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF166534))),
                        ),
                      ],
                    ),
                  ),
                  _gap(10),
                  const _Bar(0.9),
                  _gap(7),
                  const _Bar(0.55),
                ],
              ),
            ),
          ),
          Container(
            height: 52,
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home_rounded, rs.mockHome),
                Flexible(
                  flex: 2,
                  child: _Target(
                    radius: 10,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _navItem(Icons.list_alt_rounded, rs.mockMyReports, active: true),
                        ],
                      ),
                    ),
                  ),
                ),
                _navItem(Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ],
      );
}
