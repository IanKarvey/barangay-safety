import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../widgets/app_text.dart';

/// Privacy notice, as required by RA 10173 (Data Privacy Act of 2012).
///
/// Written to be *read*, not to be scrolled past. The Act requires that a data
/// subject be informed of what is collected, why, who sees it and how long it
/// is kept — a wall of legal boilerplate technically satisfies that and
/// practically does not, which is the failure mode most apps choose.
///
/// The content is deliberately specific to this system: it names the actual
/// fields collected and the actual people who can see them. A generic template
/// would be both less useful and less defensible.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  /// Bump when the notice materially changes. Consent recorded before this
  /// date no longer covers the current terms — see `privacy_consent_at` in
  /// `migration_privacy_consent.sql`.
  static final DateTime effectiveDate = DateTime(2026, 8, 16);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Privacy Notice')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          AppText(
            'How ${AppConfig.appName} handles your information',
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 6),
          Text(
            'In line with the Data Privacy Act of 2012 (Republic Act No. 10173). '
            'Effective 16 August 2026.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 24),

          _Section(
            title: 'What we collect',
            body:
                'Your name, phone number, email address and home address when you '
                'register.\n\n'
                'Your date of birth, if you choose to give it. This is optional and '
                'is used only for anonymous barangay statistics.\n\n'
                'Your GPS location at the moment you file a report, and any photos '
                'or videos you attach to it.\n\n'
                'If you are a barangay official who turns on location sharing, your '
                'live location while you are responding — and only then.',
          ),

          _Section(
            title: 'Why we collect it',
            body:
                'To send help to the right place. Your location is what tells the '
                'barangay where the emergency is, and your contact details are how '
                'they reach you about it.\n\n'
                'Reports also form the barangay’s record of what happened and how '
                'it was handled.',
          ),

          _Section(
            title: 'Who can see it',
            body:
                'Officials of your own barangay, and the city administrator.\n\n'
                'Officials of other barangays cannot see your reports.\n\n'
                'Other residents cannot see your reports, your location, or your '
                'contact details. The community heat map shows only the general '
                'areas where incidents happen — never who reported them.\n\n'
                'We do not sell your information, and we do not share it with '
                'advertisers.',
          ),

          _Section(
            title: 'How long we keep it',
            body:
                'Incident reports are kept as the barangay’s permanent record of '
                'an emergency and how it was answered.\n\n'
                'Your live location while responding is not stored as history — it '
                'is deleted when the case closes.\n\n'
                'Your account details are kept for as long as you have an account.',
          ),

          _Section(
            title: 'Your rights',
            body:
                'Under the Data Privacy Act you may ask to see the information we '
                'hold about you, correct anything that is wrong, withdraw your '
                'consent, or ask us to delete your account.\n\n'
                'You can edit your details any time from your Profile, and request '
                'deletion from the same screen.\n\n'
                'One limit worth being straight about: deleting your account does '
                'not erase incident reports. Those are the barangay’s record of a '
                'real emergency and its response. What we do instead is remove your '
                'personal details from them, so the report survives without '
                'identifying you.',
          ),

          _Section(
            title: 'If you are under 18',
            body:
                'The Data Privacy Act requires a parent or guardian to consent '
                'before a minor’s information is processed. If you are under 18, '
                'go through registration with a parent or guardian.\n\n'
                'In a genuine emergency, report first. Nothing on this screen '
                'should stop anyone getting help.',
          ),

          _Section(
            title: 'Questions or complaints',
            body:
                'Speak to your barangay hall in the first instance. You also have '
                'the right to complain to the National Privacy Commission '
                '(privacy.gov.ph).',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(title, style: AppTextStyles.heading3),
          const SizedBox(height: 6),
          AppText(
            body,
            style: AppTextStyles.body.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}
