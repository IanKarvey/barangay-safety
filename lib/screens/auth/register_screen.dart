import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../providers/barangay_provider.dart';
import '../../services/location_service.dart';
import '../../models/barangay_model.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/animated_text_field.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/app_text.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _addressController = TextEditingController();

  bool _obscurePassword = true;
  DateTime? _dateOfBirth;

  // §8 minors — only ever read when _dateOfBirth puts the account under 18.
  final _guardianNameController = TextEditingController();
  final _guardianPhoneController = TextEditingController();
  String? _guardianRelationship;

  /// True only when a date of birth is known AND under 18.
  ///
  /// An unknown DOB is deliberately NOT treated as a minor: date of birth is
  /// optional on this form, and forcing guardian details on every adult who
  /// skipped it would push people to enter a fake birthday, which is worse
  /// than not knowing.
  bool get _isMinor {
    final dob = _dateOfBirth;
    if (dob == null) return false;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years < 18;
  }

  /// RA 10173 requires consent to be given, not assumed. Defaults to false and
  /// blocks submission — a pre-ticked box is not consent.
  bool _privacyAccepted = false;
  bool _obscureConfirm = true;
  bool _isCheckingLocation = false;
  String? _selectedBarangayId;
  final _locationService = LocationService();

  final MapController _mapController = MapController();
  late final AnimationController _mapAnimController;
  late final AnimationController _cardAnimController;
  late final Animation<double> _cardSlideAnim;
  late final Animation<double> _cardFadeAnim;

  static const double _centerLat = 13.9411;
  static const double _centerLng = 121.1632;
  static const double _orbitRadius = 0.018;
  static const double _orbitZoom = 14.5;

  @override
  void initState() {
    super.initState();

    _mapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 50),
    );
    _mapAnimController.addListener(() {
      if (!mounted) return;
      final angle = _mapAnimController.value * 2 * math.pi + math.pi / 2;
      final lat = _centerLat + _orbitRadius * math.cos(angle);
      final lng = _centerLng + _orbitRadius * math.sin(angle);
      _mapController.move(LatLng(lat, lng), _orbitZoom);
    });
    _mapAnimController.repeat();

    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardSlideAnim = Tween<double>(begin: 0.18, end: 0.0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic),
    );
    _cardFadeAnim = CurvedAnimation(
      parent: _cardAnimController,
      curve: Curves.easeOut,
    );

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _cardAnimController.forward();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BarangayProvider>().loadBarangays();
    });
  }

  @override
  void dispose() {
    _mapAnimController.dispose();
    _cardAnimController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<bool> _checkWithinLipaCity() async {
    setState(() => _isCheckingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition();
      // Guarded: acquiring a GPS fix takes seconds, and a user who
      // backs out of the screen while waiting leaves this callback
      // running against a disposed State. setState() then throws
      // "setState() called after dispose()".
      if (!mounted) return false;
      final distKm = lipaCityDistanceKm(position.latitude, position.longitude);
      setState(() => _isCheckingLocation = false);
      if (distKm > 20.0) {
        HapticFeedback.heavyImpact();
        await showOutsideCitySheet(context, distKm);
        return false;
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _isCheckingLocation = false);
      return true;
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBarangayId == null) {
      showErrorSnackbar(context, 'Please select your barangay');
      return;
    }
    // Checked before the geofence call so someone outside the city is not made
    // to wait for a GPS fix only to be stopped by a checkbox.
    if (!_privacyAccepted) {
      HapticFeedback.heavyImpact();
      showErrorSnackbar(context, context.s.privacyConsentRequired);
      return;
    }
    // §8 — RA 10173 requires a guardian's consent to process a minor's data.
    // Checked before the geofence for the same reason the privacy checkbox is:
    // do not make someone wait on a GPS fix to be told about a missing field.
    if (_isMinor &&
        (_guardianNameController.text.trim().isEmpty ||
            _guardianPhoneController.text.trim().isEmpty ||
            _guardianRelationship == null)) {
      HapticFeedback.heavyImpact();
      showErrorSnackbar(context, context.s.guardianRequired);
      return;
    }

    // §12 — one person, several accounts, is how the strike system gets
    // defeated. A warning rather than a block: households genuinely share a
    // number, and refusing outright would lock out a real resident to stop a
    // hypothetical one.
    if (await _warnIfPhoneRegistered()) return;

    if (!mounted) return;
    if (!await _checkWithinLipaCity()) return;

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();

    // Registration is residents-only. Non-residents no longer create accounts
    // at all — they use the passwordless one-time flow in
    // screens/non_resident/, which needs no signup and no approval.
    final success = await auth.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.trim(),
      barangayId: _selectedBarangayId!,
      address: _addressController.text.trim(),
      dateOfBirth: _dateOfBirth,
      guardianName:
          _isMinor ? _guardianNameController.text.trim() : null,
      guardianPhone:
          _isMinor ? _guardianPhoneController.text.trim() : null,
      guardianRelationship: _isMinor ? _guardianRelationship : null,
    );

    if (!mounted) return;

    if (success) {
      HapticFeedback.lightImpact();
      Navigator.pushReplacementNamed(context, '/pending-verification');
    } else {
      HapticFeedback.heavyImpact();
      showErrorSnackbar(context, auth.error ?? 'Registration failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final barangayProvider = context.watch<BarangayProvider>();
    final auth = context.watch<AuthProvider>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Map background ───────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(_centerLat, _centerLng),
                initialZoom: _orbitZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                const AppTileLayer(),
                const AppMapAttribution(),
              ],
            ),

            // ── Dark gradient overlay ────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.38, 1.0],
                  colors: [
                    Color(0xDD001245),
                    Color(0xAA001245),
                    Color(0xF5001245),
                  ],
                ),
              ),
            ),

            // ── Top bar — back + branding ────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(height: 2),
                        Text(
                          'BARANGAY SAFETY',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.75),
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: -0.2, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),

            // ── Floating form card ───────────────────────────────────────────
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
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 40,
                        offset: Offset(0, -8),
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

                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppText(
                              'Create Account',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Join your barangay safety network',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Scrollable form
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              28, 16, 28, math.max(bottomInset, 32)),
                          physics: const BouncingScrollPhysics(),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Verification notice. Every resident account
                                // is verified in person at the barangay hall.
                                Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: AppColors.primary.withValues(alpha: 0.22)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline_rounded,
                                          color: AppColors.primary, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Resident accounts require in-person verification '
                                          'at the barangay hall. Just visiting? Use '
                                          'Emergency Report instead — no account needed.',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 11.5,
                                            color: AppColors.textSecondary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ).animate().fadeIn(duration: 220.ms).slideY(begin: -0.1),

                                const SizedBox(height: 18),

                                // Fields — staggered entrance
                                AnimatedTextField(
                                  controller: _fullNameController,
                                  labelText: context.s.fullName,
                                  prefixIcon: Icons.person_outlined,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  validator: (v) => validateRequired(v, 'Full name'),
                                ).animate(delay: 60.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                AnimatedTextField(
                                  controller: _emailController,
                                  labelText: context.s.email,
                                  prefixIcon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  validator: validateEmail,
                                ).animate(delay: 100.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                AnimatedTextField(
                                  controller: _phoneController,
                                  labelText: context.s.phoneNumber,
                                  hintText: '09XXXXXXXXX',
                                  prefixIcon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  validator: validatePhone,
                                ).animate(delay: 140.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                // Barangay dropdown
                                _buildBarangayDropdown(barangayProvider)
                                    .animate(delay: 180.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                _buildDobField()
                                    .animate(delay: 200.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                AnimatedTextField(
                                  controller: _addressController,
                                  labelText: context.s.addressOptional,
                                  prefixIcon: Icons.home_outlined,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                ).animate(delay: 220.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                AnimatedTextField(
                                  controller: _passwordController,
                                  labelText: context.s.password,
                                  prefixIcon: Icons.lock_outlined,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.next,
                                  validator: validatePassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                    onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                                  ),
                                ).animate(delay: 260.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 12),

                                AnimatedTextField(
                                  controller: _confirmPasswordController,
                                  labelText: context.s.confirmPassword,
                                  prefixIcon: Icons.lock_outlined,
                                  obscureText: _obscureConfirm,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _handleRegister(),
                                  validator: (v) {
                                    if (v != _passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                    onPressed: () => setState(
                                        () => _obscureConfirm = !_obscureConfirm),
                                  ),
                                ).animate(delay: 300.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                                const SizedBox(height: 24),

                                _buildPrivacyConsent()
                                    .animate(delay: 300.ms).fadeIn(duration: 300.ms),
                                const SizedBox(height: 14),

                                AnimatedButton(
                                  label: context.s.createAccount,
                                  isLoading: auth.isLoading || _isCheckingLocation,
                                  onPressed: _handleRegister,
                                ).animate(delay: 340.ms).fadeIn(duration: 300.ms).slideY(begin: 0.1, curve: Curves.easeOutBack),
                                const SizedBox(height: 16),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Already have an account? ',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 13,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ).animate(delay: 380.ms).fadeIn(duration: 280.ms),
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
    );
  }



  /// Optional so it can never block a registration. §10's 45+ demographic is
  /// worth having, but not at the cost of someone failing to sign up during an
  /// emergency — `get_age_demographics()` already reports missing dates under
  /// an explicit `unknown` bracket rather than guessing.

  /// Consent must be an explicit act, unticked by default. RA 10173 treats
  /// consent as freely given, specific and informed — a pre-ticked box or an
  /// "by continuing you agree" line is none of those.
  Widget _buildPrivacyConsent() {
    final t = context.s;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _privacyAccepted,
            onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppText(t.privacyConsentLabel, style: AppTextStyles.bodySmall),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/privacy'),
                child: AppText(
                  t.readNotice,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// §12 — returns true if the user chose to stop and use their existing
  /// account.
  Future<bool> _warnIfPhoneRegistered() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return false;

    final taken = await AuthService().isPhoneAlreadyRegistered(phone);
    if (!taken || !mounted) return false;

    HapticFeedback.heavyImpact();
    final proceed = await showFrostedConfirm(
      context,
      title: context.s.phoneAlreadyUsedTitle,
      message: context.s.phoneAlreadyUsedBody,
      confirmLabel: context.s.continueAnyway,
      cancelLabel: context.s.backToLogin,
      icon: Icons.info_outline_rounded,
    );

    // Cancel means "I already have an account" — send them where that helps.
    if (proceed != true) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return true;
    }
    return false;
  }

  /// §8 — appears only once the chosen date of birth is under 18.
  ///
  /// Deliberately not a permanently visible section: an adult filling this
  /// form should never see fields about guardians, and a section that greys
  /// itself out still reads as something you might have to deal with.
  Widget _buildGuardianSection() {
    final t = context.s;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  t.guardianSectionTitle,
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          AppText(t.guardianSectionWhy, style: AppTextStyles.caption),
          const SizedBox(height: 12),
          TextFormField(
            controller: _guardianNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: t.guardianName,
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            validator: (v) => _isMinor && (v == null || v.trim().isEmpty)
                ? t.fieldRequired
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _guardianPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: t.guardianPhone,
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
            validator: (v) => _isMinor && (v == null || v.trim().isEmpty)
                ? t.fieldRequired
                : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _guardianRelationship,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t.guardianRelationship,
              prefixIcon: const Icon(Icons.people_outline_rounded),
            ),
            // Value is the canonical key, label is the translation.
            //
            // These were the same string before: registering in Tagalog stored
            // "Magulang" in the database, so an official reviewing the account
            // in English saw Tagalog — and any future query for "parent" would
            // have missed every account created in the other language.
            items: const [
              GuardianRelationship.parent,
              GuardianRelationship.grandparent,
              GuardianRelationship.sibling,
              GuardianRelationship.legalGuardian,
              GuardianRelationship.other,
            ]
                .map((key) => DropdownMenuItem(
                      value: key,
                      child: AppText(GuardianRelationship.label(t, key)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _guardianRelationship = v),
            validator: (v) => _isMinor && v == null ? t.fieldRequired : null,
          ),
        ],
      ),
    );
  }

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
        const Padding(
          padding: EdgeInsets.only(left: 12, top: 5),
          child: SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: AppText(
            t.dobWhyAsk,
            style: AppTextStyles.caption,
          ),
        ),
        if (_isMinor) _buildGuardianSection(),
      ],
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Opens at a plausible adult birth year rather than today, so the common
      // case is a couple of taps instead of scrolling back decades.
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.s.dateOfBirth,
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  Widget _buildBarangayDropdown(BarangayProvider barangayProvider) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: DropdownButtonFormField<String>(
        value: _selectedBarangayId,
        decoration: InputDecoration(
          labelText: context.s.selectBarangay,
          prefixIcon: Icon(Icons.location_city_outlined, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
        items: barangayProvider.barangays.map((BarangayModel b) {
          return DropdownMenuItem(
            value: b.id,
            child: AppText(
              b.name,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            ),
          );
        }).toList(),
        onChanged: (value) => setState(() => _selectedBarangayId = value),
        validator: (v) => v == null ? 'Please select a barangay' : null,
      ),
    );
  }
}
