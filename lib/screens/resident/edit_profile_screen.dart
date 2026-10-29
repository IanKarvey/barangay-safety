import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/animated_text_field.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/app_text.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  DateTime? _dateOfBirth;
  bool _isLoading = false;

  late final AnimationController _cardAnimController;
  late final Animation<double> _cardSlideAnim;
  late final Animation<double> _cardFadeAnim;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _addressController = TextEditingController(text: user?.address ?? '');
    _dateOfBirth = user?.dateOfBirth;

    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _cardSlideAnim = Tween<double>(begin: 0.18, end: 0.0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic),
    );
    _cardFadeAnim = CurvedAnimation(
      parent: _cardAnimController,
      curve: Curves.easeOut,
    );

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _cardAnimController.forward();
    });
  }

  @override
  void dispose() {
    _cardAnimController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.updateProfile({
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        // Date-only string, no timezone — a birthday must not shift across
        // midnight depending on where the device is.
        'date_of_birth': _dateOfBirth?.toIso8601String().split('T').first,
      });
      if (mounted) {
        HapticFeedback.lightImpact();
        showSuccessSnackbar(context, 'Profile updated');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        showErrorSnackbar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final initials = (user?.fullName ?? '')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: LoadingOverlay(
        isLoading: _isLoading,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Deep navy gradient background ────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF001245), Color(0xFF0D2272), Color(0xFF001A6E)],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // ── Decorative soft circles ──────────────────────────────────────
              Positioned(
                top: -70,
                right: -50,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Positioned(
                top: 80,
                left: -90,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                ),
              ),

              // ── Top bar + avatar header ──────────────────────────────────────
              SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          const Flexible(child: AppText(
                            'Edit Profile',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          )),
                          const Spacer(),
                          TextButton(
                            onPressed: _isLoading ? null : _save,
                            child: Text(
                              'Save',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _isLoading
                                    ? Colors.white38
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Avatar
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF001245)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AppText(
                          initials.isEmpty ? '?' : initials,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.6, 0.6),
                          duration: 550.ms,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 400.ms),

                    const SizedBox(height: 12),

                    AppText(
                      user?.fullName ?? '',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ).animate(delay: 80.ms).fadeIn(duration: 400.ms).slideY(
                          begin: 0.15,
                          end: 0,
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        ),

                    const SizedBox(height: 6),

                    // Role chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        (user?.role ?? '').replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ).animate(delay: 160.ms).fadeIn(duration: 400.ms),

                    const SizedBox(height: 22),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 450.ms)
                  .slideY(
                    begin: -0.08,
                    end: 0,
                    duration: 450.ms,
                    curve: Curves.easeOutCubic,
                  ),

              // ── Sliding white form card ──────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _cardAnimController,
                  builder: (_, child) => FadeTransition(
                    opacity: _cardFadeAnim,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        _cardSlideAnim.value *
                            MediaQuery.of(context).size.height,
                      ),
                      child: child,
                    ),
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.62,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x50000000),
                          blurRadius: 48,
                          offset: Offset(0, -10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              18,
                              24,
                              math.max(bottomInset, 32),
                            ),
                            physics: const BouncingScrollPhysics(),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _sectionLabel('Personal Information'),
                                  const SizedBox(height: 14),

                                  AnimatedTextField(
                                    controller: _nameController,
                                    labelText: context.s.fullName,
                                    prefixIcon: Icons.person_outlined,
                                    textCapitalization: TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) =>
                                        validateRequired(v, 'Full name'),
                                    onChanged: (_) => setState(() {}),
                                  )
                                      .animate(delay: 100.ms)
                                      .fadeIn(duration: 320.ms)
                                      .slideY(
                                        begin: 0.14,
                                        curve: Curves.easeOutCubic,
                                      ),

                                  const SizedBox(height: 14),

                                  AnimatedTextField(
                                    controller: _phoneController,
                                    labelText: context.s.phoneNumber,
                                    prefixIcon: Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    validator: validatePhone,
                                  )
                                      .animate(delay: 150.ms)
                                      .fadeIn(duration: 320.ms)
                                      .slideY(
                                        begin: 0.14,
                                        curve: Curves.easeOutCubic,
                                      ),

                                  const SizedBox(height: 14),

                                  AnimatedTextField(
                                    controller: _addressController,
                                    labelText: context.s.homeAddress,
                                    prefixIcon: Icons.home_outlined,
                                    textInputAction: TextInputAction.done,
                                    textCapitalization: TextCapitalization.words,
                                    maxLines: 2,
                                    onFieldSubmitted: (_) => _save(),
                                  )
                                      .animate(delay: 200.ms)
                                      .fadeIn(duration: 320.ms)
                                      .slideY(
                                        begin: 0.14,
                                        curve: Curves.easeOutCubic,
                                      ),

                                  const SizedBox(height: 14),

                                  _buildDobField()
                                      .animate(delay: 220.ms)
                                      .fadeIn(duration: 320.ms)
                                      .slideY(
                                        begin: 0.14,
                                        curve: Curves.easeOutCubic,
                                      ),

                                  const SizedBox(height: 24),

                                  _sectionLabel('Account Information'),
                                  const SizedBox(height: 12),

                                  _infoRow(
                                    Icons.email_outlined,
                                    'Email',
                                    user?.email ?? '',
                                  ),
                                  _infoRow(
                                    Icons.location_city_outlined,
                                    'Barangay',
                                    user?.barangayName ?? '',
                                  ),
                                  _infoRow(
                                    Icons.badge_outlined,
                                    'Role',
                                    (user?.role ?? '')
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                  ),

                                  const SizedBox(height: 6),

                                  Text(
                                    'Email, barangay, and role cannot be changed here.',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  AnimatedButton(
                                    label: context.s.saveChanges,
                                    isLoading: _isLoading,
                                    onPressed: _save,
                                  )
                                      .animate(delay: 240.ms)
                                      .fadeIn(duration: 320.ms)
                                      .slideY(
                                        begin: 0.14,
                                        curve: Curves.easeOutCubic,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => AppText(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.9,
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  /// Editable here as well as at signup, because DOB capture only began
  /// 2026-08-11 — every account created before that has none, and without a
  /// way to fill it in, §10's 45+ demographic would stay near zero for years.
  Widget _buildDobField() {
    final t = context.s;
    final label = _dateOfBirth == null
        ? t.dobNotSet
        : DateFormat('MMM d, yyyy').format(_dateOfBirth!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _pickDob,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: t.dateOfBirthOptional,
              prefixIcon: const Icon(Icons.cake_outlined),
            ),
            child: AppText(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: _dateOfBirth == null
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: AppText(t.dobWhyAsk, style: AppTextStyles.caption),
        ),
      ],
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.s.dateOfBirth,
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

}
