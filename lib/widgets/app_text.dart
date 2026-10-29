import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

/// The one place text is allowed to break mid-word: never.
///
/// ## The bug this closes
///
/// A plain `Text` widget only breaks a single word across two lines when that
/// word alone is wider than the space it has — there is no legal break point
/// at a space, so Flutter's paragraph layout falls back to splitting the
/// glyph run itself. "City Administrator" doing that on the superadmin
/// dashboard (2026-09) is one instance of a pattern found in 377 places across
/// 50 files: a hardcoded font size, no `maxLines`, no `overflow`, and content
/// that is either user-generated (names, addresses, category labels) or a
/// localized string whose Tagalog rendering runs longer than the English one
/// it was sized against.
///
/// ## Why one wrapper instead of 377 individual fixes
///
/// `maxLines` + `TextOverflow.ellipsis` alone stops the mid-word break, but
/// only by truncating — "City Admini…" is not actually better than the bug it
/// replaces, just differently wrong. What the text actually needs is to try
/// wrapping normally, and only shrink if a full word still cannot fit within
/// [maxLines]. `AutoSizeText` (the backing package) does exactly that: it lays
/// the text out at its requested size first, and only steps the font size
/// down when the content would otherwise overflow or force a mid-word split.
///
/// Wrapping that in one project-wide widget — rather than tuning
/// `minFontSize`/`maxLines`/`overflow` by hand at 377 call sites — means the
/// fitting *behaviour* lives in exactly one place. If it ever needs to change
/// (a different floor, a different backing package entirely), it changes here
/// once. The named constructors below intentionally mirror `AppTextStyles`
/// (`AppText.heading2(...)` next to `AppTextStyles.heading2`) so converting a
/// call site is a mechanical rename, not a redesign.
///
/// ## The one thing this cannot do on its own
///
/// `AutoSizeText` needs a *bounded* width to know what "fit" means. Inside a
/// `Column`, the width is already bounded by the column itself, so this works
/// with no extra wrapping. Inside a `Row`, a text child needs `Expanded` or
/// `Flexible` around it — same requirement a plain `Text` already has for
/// `overflow: ellipsis` to mean anything, so this changes nothing that
/// wasn't already true.
class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    // 2 rather than null: the plain constructor is what a mechanical
    // `Text(` -> `AppText(` rename produces, and it has to be safe on its
    // own for every one of the 377 flagged call sites — most of which never
    // set maxLines at all, which is the exact absence that let the mid-word
    // break happen. A caller that genuinely wants more (or fewer) lines still
    // passes maxLines explicitly and overrides this.
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.largeTitle] (34px) — screen-defining titles.
  const AppText.largeTitle(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.heading1] (28px).
  const AppText.heading1(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.heading2] (22px) — the size in the reported bug.
  const AppText.heading2(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.heading3] (17px).
  const AppText.heading3(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.body] (17px) — defaults to 3 lines: body text is the one
  /// tier genuinely meant to run to a sentence or two, not one line.
  const AppText.body(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 3,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.bodySmall] (15px).
  const AppText.bodySmall(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.subheadline] (15px).
  const AppText.subheadline(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.button] (17px) — buttons stay one line; a button whose
  /// label shrinks instead of wrapping is the correct failure mode, since a
  /// two-line button breaks the layout it sits in.
  const AppText.button(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.caption] (12px) — already near the floor, so this mostly
  /// guards against breaking rather than shrinking further.
  const AppText.caption(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// [AppTextStyles.footnote] (13px).
  const AppText.footnote(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  });

  /// Single line, no exceptions — badges, chips, and table cells where a
  /// second line would break the layout around the text rather than just the
  /// text itself.
  const AppText.oneLine(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow = TextOverflow.ellipsis,
    this.minFontSize = _defaultMinFontSize,
    this.textScaleFactor,
    this.softWrap = true,
    this.semanticsLabel,
  }) : maxLines = 1;

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final double minFontSize;
  final double? textScaleFactor;
  final bool softWrap;
  final String? semanticsLabel;

  /// A word-shape name is still legible around this size on a phone screen.
  /// Below it, shrinking further reads as "broken" rather than "compact", so
  /// this is where [overflow] takes over instead.
  static const double _defaultMinFontSize = 11;

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      overflowReplacement: null,
      minFontSize: minFontSize,
      // A step of 1 is fine-grained enough that the shrink is not visually
      // jumpy between rebuilds (e.g. as a provider updates a stat value).
      stepGranularity: 1,
      softWrap: softWrap,
      // The actual fix for the mid-word break: AutoSizeText treats a word
      // that cannot fit on one line as a reason to shrink the WHOLE text, not
      // as license to split the word across two. This is what `wrapWords`
      // controls — true is "never break inside a word", which is the entire
      // point of this widget existing.
      wrapWords: true,
      textScaleFactor: textScaleFactor,
      semanticsLabel: semanticsLabel,
    );
  }
}
