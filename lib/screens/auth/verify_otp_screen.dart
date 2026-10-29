import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/app_text.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String email;

  const VerifyOtpScreen({super.key, required this.email});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen>
    with TickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  int _resendCountdown = 60;
  Timer? _timer;

  // Shake animation
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // Green fill state — which boxes have been confirmed correct
  final Set<int> _filledBoxes = {};
  bool _isAccepted = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -9.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -9.0, end: 9.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 9.0, end: -5.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.linear));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown == 0) {
        t.cancel();
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 8) {
      showErrorSnackbar(context, 'Please enter the complete 8-digit code');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: _otp,
        type: OtpType.signup,
      );

      if (!mounted) return;
      await _animateSuccess();
    } on AuthException catch (e) {
      if (!mounted) return;
      showErrorSnackbar(context, e.message);
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Verification failed. Please try again.');
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _animateSuccess() async {
    setState(() => _isAccepted = true);
    for (int i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 65));
      if (!mounted) return;
      setState(() => _filledBoxes.add(i));
      HapticFeedback.lightImpact();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/resident');
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0) return;
    setState(() => _isResending = true);

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (!mounted) return;
      showSuccessSnackbar(context, 'New code sent to ${widget.email}');
      _startResendTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      showErrorSnackbar(context, e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _onDigitChanged(String value, int index) {
    if (value.length == 1 && index < 7) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_otp.length == 8 && !_isVerifying) _verify();
  }

  void _onKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // ── Icon ──────────────────────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.0, 0.0),
                    end: const Offset(1.0, 1.0),
                    duration: 500.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 300.ms),
              const SizedBox(height: 28),

              // ── Title ─────────────────────────────────────────────────────
              const AppText(
                'Check your email',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              )
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.2, end: 0, duration: 380.ms, curve: Curves.easeOutCubic),

              const SizedBox(height: 10),
              Text(
                'We sent an 8-digit verification code to',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 160.ms)
                  .fadeIn(duration: 300.ms),
              const SizedBox(height: 4),
              AppText(
                widget.email,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 300.ms),
              const SizedBox(height: 44),

              // ── OTP Boxes ─────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnim.value, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (i) {
                    final isFilled = _filledBoxes.contains(i);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: 38,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isFilled
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFilled
                                ? AppColors.success
                                : _focusNodes[i].hasFocus
                                    ? AppColors.primary
                                    : AppColors.divider,
                            width: isFilled ? 2 : 1.5,
                          ),
                        ),
                        child: KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (e) => _onKeyEvent(e, i),
                          child: isFilled
                              ? const Center(
                                  child: Icon(
                                    Icons.check_rounded,
                                    color: AppColors.success,
                                    size: 22,
                                  ),
                                )
                              : TextFormField(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    border: InputBorder.none,
                                    filled: false,
                                  ),
                                  onChanged: (v) => _onDigitChanged(v, i),
                                ),
                        ),
                      )
                          .animate(delay: Duration(milliseconds: 280 + i * 70))
                          .scale(
                            begin: const Offset(0.0, 0.0),
                            end: const Offset(1.0, 1.0),
                            duration: 380.ms,
                            curve: Curves.easeOutBack,
                          )
                          .fadeIn(duration: 250.ms),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 40),

              // ── Verify Button ─────────────────────────────────────────────
              AnimatedButton(
                label: _isAccepted ? 'Verified!' : 'Verify Email',
                isLoading: _isVerifying,
                backgroundColor: _isAccepted ? AppColors.success : AppColors.primary,
                onPressed: _isVerifying || _isAccepted ? null : _verify,
              )
                  .animate(delay: 900.ms)
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.15, end: 0, duration: 380.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 24),

              // ── Resend ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive a code? ",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  _isResending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : GestureDetector(
                          onTap: _resendCountdown == 0 ? _resend : null,
                          child: Text(
                            _resendCountdown > 0
                                ? 'Resend in ${_resendCountdown}s'
                                : 'Resend',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _resendCountdown > 0
                                  ? AppColors.textSecondary
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                ],
              )
                  .animate(delay: 1000.ms)
                  .fadeIn(duration: 300.ms),
            ],
          ),
        ),
      ),
    );
  }
}
