import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/response_strings.dart';
import '../../services/tutorial_service.dart';
import '../../utils/constants.dart';

/// A pretend report, for practising without bothering anyone.
///
/// It looks and flows like the real thing — pick what happened, write a few
/// words, press Submit — but it is a sealed room: it uses no providers, no
/// location, no camera and no network, so there is nothing it COULD send. The
/// orange bar saying "Practice only / Pagsasanay lang" stays on screen the whole
/// time so nobody mistakes it for a real report, and the only thing recorded is
/// that someone practised (in the tutorial log, flagged as practice).
class PracticeReportScreen extends StatefulWidget {
  const PracticeReportScreen({super.key, this.log});

  final TutorialLog? log;

  @override
  State<PracticeReportScreen> createState() => _PracticeReportScreenState();
}

class _PracticeReportScreenState extends State<PracticeReportScreen> {
  late final TutorialLog _log = widget.log ?? TutorialService();

  /// 0 choose, 1 write, 2 submit, 3 done.
  int _stage = 0;
  String? _category;
  final _text = TextEditingController();

  /// Calm categories only: the real app diverts a fire or a robbery to a
  /// phone-this-agency screen, which would be the wrong thing to rehearse here.
  static const _choices = <(String, IconData, Color)>[
    ('Noise Disturbance', Icons.volume_up_rounded, Color(0xFF0284C7)),
    ('Public Disturbance', Icons.groups_rounded, Color(0xFFEA580C)),
    ('Vandalism', Icons.broken_image_rounded, Color(0xFF7C3AED)),
    ('Suspicious Activity', Icons.visibility_rounded, Color(0xFF059669)),
  ];

  @override
  void initState() {
    super.initState();
    // Recorded as practice, so usage numbers never mistake it for a real report.
    _log.opened(source: 'button', practice: true);
    assert(AppConfig.incidentCategories.contains('Noise Disturbance'));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _restart() => setState(() {
        _stage = 0;
        _category = null;
        _text.clear();
      });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final t = context.s;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(rs.practiceTitle)),
      body: SafeArea(
        child: Column(
          children: [
            // Always on screen.
            Container(
              width: double.infinity,
              color: const Color(0xFFF97316),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Text(
                    rs.practiceOnly,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rs.practiceHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: switch (_stage) {
                      0 => _choose(rs, t),
                      1 => _write(rs),
                      2 => _submit(rs, t),
                      _ => _done(rs),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      );

  Widget _choose(ResponseStrings rs, AppStrings t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(rs.practiceStep1),
          for (final (key, icon, color) in _choices) ...[
            Material(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() {
                  _category = key;
                  _stage = 1;
                }),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 34),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(categoryLabel(t, key),
                              style: TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w800, color: color)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      );

  Widget _write(ResponseStrings rs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(rs.practiceStep2),
          TextField(
            controller: _text,
            maxLines: 4,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: rs.practiceTypeHint,
              hintStyle: const TextStyle(fontSize: 17),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => _stage = 2),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
            child: Text(rs.next, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => setState(() => _stage = 2),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: Text(rs.practiceSkipWriting, style: const TextStyle(fontSize: 18)),
          ),
        ],
      );

  Widget _submit(ResponseStrings rs, AppStrings t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(rs.practiceStep3),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(categoryLabel(t, _category ?? ''),
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                if (_text.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_text.text.trim(), style: const TextStyle(fontSize: 18)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => setState(() => _stage = 3),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(66),
              backgroundColor: AppColors.success,
            ),
            icon: const Icon(Icons.send_rounded, size: 28),
            label: Text(rs.mockSubmit,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
        ],
      );

  Widget _done(ResponseStrings rs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded, size: 84, color: AppColors.success),
          const SizedBox(height: 12),
          Text(
            rs.practiceSubmitted,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, height: 1.35, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _restart,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
            child: Text(rs.practiceAgain,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
            child: Text(rs.close, style: const TextStyle(fontSize: 20)),
          ),
        ],
      );
}
