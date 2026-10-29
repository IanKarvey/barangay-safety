import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/non_resident_provider.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/language_toggle.dart';
import '../../utils/helpers.dart';
import '../../widgets/animated_text_field.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/app_text.dart';

/// Passwordless entry for non-residents — contact number + name, nothing else.
///
/// No barangay picker: it is auto-detected from GPS. No password, no OTP —
/// see the security note in `supabase/migration_non_resident_sessions.sql`.
class NonResidentLoginScreen extends StatefulWidget {
  const NonResidentLoginScreen({super.key});

  @override
  State<NonResidentLoginScreen> createState() =>
      _NonResidentLoginScreenState();
}

class _NonResidentLoginScreenState extends State<NonResidentLoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 3.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final provider = context.read<NonResidentProvider>();
    final ok = await provider.signIn(
      phone: _phoneController.text.trim(),
      fullName: _nameController.text.trim(),
    );

    if (!mounted) return;

    if (ok) {
      HapticFeedback.lightImpact();
      Navigator.pushReplacementNamed(context, '/non-resident');
    } else {
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      showErrorSnackbar(
          context, provider.error ?? 'Could not start your session.');
      provider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<NonResidentProvider, bool>(
        (p) => p.isLoading);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 8,
              right: 16,
              child: LanguageToggle(),
            ),
            Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: AnimatedBuilder(
              animation: _shakeAnim,
              builder: (context, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Emblem
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.emergency_share_rounded,
                            size: 38, color: AppColors.primary),
                      ),
                    )
                        .animate()
                        .scale(
                            begin: const Offset(0.6, 0.6),
                            end: const Offset(1, 1),
                            duration: 560.ms,
                            curve: Curves.easeOutBack)
                        .fadeIn(duration: 320.ms),

                    const SizedBox(height: 24),

                    AppText(context.s.emergencyReport,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.heading1)
                        .animate(delay: 120.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 8),

                    Text(
                      context.s.emergencyReportSubtitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 32),

                    AnimatedTextField(
                      controller: _phoneController,
                      labelText: context.s.contactNumber,
                      hintText: '09XXXXXXXXX',
                      prefixIcon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      validator: validatePhone,
                    )
                        .animate(delay: 280.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.14, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 16),

                    AnimatedTextField(
                      controller: _nameController,
                      labelText: context.s.fullName,
                      prefixIcon: Icons.person_rounded,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      validator: (v) => validateRequired(v, 'Full name'),
                      onFieldSubmitted: (_) => _submit(),
                    )
                        .animate(delay: 360.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.14, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 20),

                    // Why we need location
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.my_location_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your location is required. It decides which '
                              'barangay receives your report and lets them '
                              'find you.',
                              style: AppTextStyles.caption,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate(delay: 440.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 24),

                    AnimatedButton(
                      label: context.s.continueLabel,
                      icon: Icons.arrow_forward_rounded,
                      isLoading: isLoading,
                      onPressed: isLoading ? null : _submit,
                    )
                        .animate(delay: 520.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.14, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pushReplacementNamed(
                              context, '/login'),
                      child: Text(context.s.haveAccount),
                    ).animate(delay: 600.ms).fadeIn(duration: 300.ms),
                  ],
                ),
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
