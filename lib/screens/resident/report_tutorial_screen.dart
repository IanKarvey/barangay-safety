import 'package:flutter/material.dart';

import '../../l10n/response_strings.dart';
import '../../services/speech_service.dart';
import '../../services/tutorial_service.dart';
import '../../utils/constants.dart';
import '../../widgets/tutorial_illustration.dart';
import 'practice_report_screen.dart';

/// "How to Report": seven short steps, one per screen, for people who forget how
/// the app works — an older relative, someone who rarely uses a phone.
///
/// Built for being read slowly and tapped with a thumb that may not be steady:
///   * one idea per screen, a picture with the thing to press ringed in orange;
///   * body text 20, titles 26, everything scales with the phone's font setting;
///   * every button is at least 56 tall, with a word on it, not just an icon;
///   * a Read Aloud button speaks the step in the app's language;
///   * Back and Close are always there, so nobody is ever stuck inside it.
///
/// Opened from the big button on the home screen, the "?" on the report form
/// (at the step the person is on), and automatically once after first sign-in.
class ReportTutorialScreen extends StatefulWidget {
  const ReportTutorialScreen({
    super.key,
    this.source = 'button',
    this.initialStep = 0,
    this.speech,
    this.log,
  });

  /// `auto` (first sign-in), `button` (home screen) or `form_help` (the "?").
  final String source;
  final int initialStep;

  /// Injected by tests; the phone's speech engine otherwise.
  final SpeechService? speech;
  final TutorialLog? log;

  @override
  State<ReportTutorialScreen> createState() => _ReportTutorialScreenState();
}

class _ReportTutorialScreenState extends State<ReportTutorialScreen> {
  late final SpeechService _speech = widget.speech ?? FlutterTtsSpeech();
  late final TutorialLog _log = widget.log ?? TutorialService();

  late int _step = widget.initialStep.clamp(0, ResponseStrings.tutorialStepCount - 1);
  late int _furthest = _step;
  Future<String?>? _logId;
  bool _completed = false;
  bool _noVoice = false;

  static const _total = ResponseStrings.tutorialStepCount;
  bool get _isLast => _step == _total - 1;

  @override
  void initState() {
    super.initState();
    _logId = _log.opened(source: widget.source);
  }

  @override
  void dispose() {
    _speech.stop();
    if (widget.speech == null) _speech.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final id = await _logId;
    await _log.progress(id, stepsViewed: _furthest + 1, completed: _completed);
  }

  Future<void> _go(int to) async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _step = to.clamp(0, _total - 1);
      if (_step > _furthest) _furthest = _step;
      _noVoice = false;
    });
    _record();
  }

  Future<void> _finish() async {
    _completed = true;
    await _record();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _close() async {
    await _record();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _toggleSpeech() async {
    if (_speech.speaking.value) {
      await _speech.stop();
      return;
    }
    final rs = context.rs;
    final ok = await _speech.speak(
      '${rs.stepTitle(_step)}. ${rs.stepText(_step)}',
      rs.language,
    );
    if (mounted) setState(() => _noVoice = !ok);
  }

  Future<void> _practice() async {
    await _speech.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticeReportScreen(log: _log)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;

    return PopScope(
      onPopInvokedWithResult: (_, __) => _speech.stop(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  // ── Top: where am I, and a way out ────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            rs.stepOf(_step + 1, _total),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _close,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(56, 56),
                            foregroundColor: AppColors.textPrimary,
                          ),
                          icon: const Icon(Icons.close_rounded, size: 26),
                          label: Text(rs.close, style: const TextStyle(fontSize: 18)),
                        ),
                      ],
                    ),
                  ),
                  _Dots(count: _total, current: _step),

                  // ── The step ──────────────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: TutorialIllustration(step: _step),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            rs.stepTitle(_step),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            rs.stepText(_step),
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.4,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<bool>(
                            valueListenable: _speech.speaking,
                            builder: (context, speaking, _) => OutlinedButton.icon(
                              onPressed: _toggleSpeech,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                side: const BorderSide(color: AppColors.primary, width: 2),
                                foregroundColor: AppColors.primary,
                              ),
                              icon: Icon(
                                speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                                size: 30,
                              ),
                              label: Text(
                                speaking ? rs.stopReading : rs.readAloud,
                                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (_noVoice)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                rs.speechUnavailable,
                                style: const TextStyle(
                                    fontSize: 17, color: AppColors.warning, fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (_isLast) ...[
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: _practice,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                              ),
                              icon: const Icon(Icons.edit_note_rounded, size: 30),
                              label: Text(
                                rs.tryIt,
                                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom: Back / Next ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _step == 0
                              ? const SizedBox.shrink()
                              : OutlinedButton.icon(
                                  onPressed: () => _go(_step - 1),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(60),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  icon: const Icon(Icons.arrow_back_rounded, size: 26),
                                  // Scales down instead of wrapping letter by
                                  // letter on a narrow phone or a large font.
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(rs.back,
                                        maxLines: 1,
                                        style: const TextStyle(fontSize: 19)),
                                  ),
                                ),
                        ),
                        SizedBox(width: _step == 0 ? 0 : 12),
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: _isLast ? _finish : () => _go(_step + 1),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(60),
                              backgroundColor: _isLast ? AppColors.success : AppColors.primary,
                            ),
                            icon: Icon(
                              _isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                              size: 26,
                            ),
                            iconAlignment: IconAlignment.end,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isLast ? rs.done : rs.next,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == current ? 26 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i <= current ? AppColors.primary : AppColors.divider,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ],
        ),
      );
}
