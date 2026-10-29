import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_text.dart';
import 'web_build.dart';

/// Sign-in for the web dashboard.
///
/// ## Why not reuse `LoginScreen`
///
/// The mobile login screen animates a live `FlutterMap` behind the form and
/// drives `_mapController.move()` on a timer. On a phone that is the first
/// impression; in an admin browser tab it is a tile-fetching background task
/// running behind a two-field form, and the throttling that made it acceptable
/// on mobile was tuned for a phone's frame budget, not a desktop browser's.
///
/// ## The split panel is not decoration
///
/// A centred card on a 2560px monitor is a small box adrift in an empty page —
/// which is exactly how the first version of this screen looked. The brand
/// panel gives the width something to do, and it carries the one thing a
/// shared barangay desktop genuinely needs to say before anyone types a
/// password: which system this is, and who it is for. Below 900px the panel is
/// dropped entirely rather than stacked, because on a narrow window it would
/// push the form itself below the fold.
///
/// ## The error mapping is shared on purpose
///
/// `AuthProvider.signIn` already maps `email_not_confirmed`,
/// `account_suspended` and `no_internet` to stable codes, so both surfaces
/// interpret a failure the same way. The one difference is the final case: the
/// mobile screen prints the raw provider string, which is how "Refresh Token
/// Not Found" reached a user verbatim (reported 2026-09-19). Here anything
/// unmapped becomes a human sentence and the raw text never reaches the UI.
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(_email.text.trim(), _password.text);
    if (!mounted) return;

    if (ok) {
      final user = auth.user;
      // A resident signing in here is not an error — the shell renders the
      // "use the mobile app" screen for them. Loading dashboard data they are
      // not allowed to see would just be a wasted round trip.
      if (user != null && (user.isAdmin || user.isSuperAdmin)) {
        widget.onSignedIn();
      }
      return;
    }

    showErrorSnackbar(context, _messageFor(auth.error));
  }

  /// Turns a provider error code into something a person can act on.
  String _messageFor(String? code) => switch (code) {
        'email_not_confirmed' =>
          'This account has not been confirmed yet. Check your email for the '
              'confirmation link.',
        'account_suspended' =>
          'This account is suspended. Contact the city administrator.',
        'no_internet' =>
          'No internet connection. Check your network and try again.',
        'Invalid login credentials' =>
          'Incorrect email or password. Please try again.',
        // Everything else — including an expired or missing session, which
        // Supabase words as "Refresh Token Not Found" — is simply a failed
        // sign-in from the user's point of view. Raw provider text helps nobody.
        _ => 'Could not sign in. Please check your details and try again.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showPanel = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (showPanel) const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 4,
                child: _form(constraints),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _form(BoxConstraints constraints) {
    final loading = context.watch<AuthProvider>().isLoading;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Only shown when the brand panel is hidden, so the screen is
                // never without the mark entirely.
                if (constraints.maxWidth < 900) ...[
                  Center(
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 56,
                      height: 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                AppText(
                  'Sign in',
                  style: AppTextStyles.heading1.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                AppText.body(
                  'Enter your credentials to access the dashboard.',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                _FieldLabel('Email'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: validateEmail,
                  decoration: const InputDecoration(
                    hintText: 'you@barangay.gov.ph',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 18),
                _FieldLabel('Password'),
                const SizedBox(height: 7),
                TextFormField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Text(
                            'Sign in',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.phone_android_rounded,
                          size: 17, color: AppColors.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText.caption(
                          'This dashboard is for barangay officials and '
                          'administrators. Residents report incidents through '
                          'the mobile app.',
                          maxLines: 3,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: AppText.caption(
                    'build $kBuildId',
                    maxLines: 1,
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary, fontSize: 10),
                  ),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppText.caption(
      text,
      style: AppTextStyles.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// The left half: brand mark, what the system is, and who it serves.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), AppColors.primaryDark],
        ),
      ),
      child: Stack(
        children: [
          // Two soft blooms rather than a flat fill — a single solid gradient
          // across half a 2560px screen reads as a printing error.
          Positioned(
            top: -120,
            right: -90,
            child: _Glow(size: 380, opacity: 0.16),
          ),
          const Positioned(
            bottom: -140,
            left: -110,
            child: _Glow(size: 420, opacity: 0.10),
          ),
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 34,
                        height: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: AppText.heading3(
                        AppConfig.appName,
                        maxLines: 1,
                        style: AppTextStyles.heading3.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                AppText(
                  'Incident reporting,\nanswered in minutes.',
                  maxLines: 3,
                  style: AppTextStyles.largeTitle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.8,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 100.ms)
                    .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 18),
                AppText.body(
                  'Every report from your barangay, the moment it is filed — '
                  'with the photo, the exact location, and who sent it.',
                  maxLines: 3,
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.55,
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 220.ms),
                const SizedBox(height: 44),
                ...[
                  (Icons.bolt_rounded, 'Reports arrive live',
                      'No calls, no walk-ins, no waiting for a handover.'),
                  (Icons.route_rounded, 'Tracked end to end',
                      'Verify, assign, dispatch, resolve — the resident sees every step.'),
                  (Icons.insights_rounded, 'Patterns you can act on',
                      'Heat maps and analytics built from your own records.'),
                ].indexed.map(
                  (e) => _Feature(
                    icon: e.$2.$1,
                    title: e.$2.$2,
                    body: e.$2.$3,
                  )
                      .animate()
                      .fadeIn(
                          duration: 400.ms,
                          delay: Duration(milliseconds: 340 + e.$1 * 90))
                      .slideX(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.location_city_rounded,
                        size: 15, color: Colors.white54),
                    const SizedBox(width: 7),
                    Expanded(
                      child: AppText.caption(
                        'Lipa City, Batangas',
                        maxLines: 1,
                        style: AppTextStyles.caption
                            .copyWith(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.bodySmall(
                  title,
                  maxLines: 1,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                AppText.caption(
                  body,
                  maxLines: 2,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.45,
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

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: opacity),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
