import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/app_text.dart';

/// Splits text into individual characters and stagger-animates each one in.
/// Equivalent to GSAP SplitText — use on hero headings and key titles.
///
/// Characters are grouped into words before being handed to [Wrap], not laid
/// out individually. A bare `Wrap` of one-character children can break the
/// line between *any* two characters once it runs out of room — including
/// inside a word — which is worse than plain `Text`'s default of only
/// breaking a word when the word itself doesn't fit. Wrapping each word's
/// characters in their own unbreakable `Flex` means `Wrap` can only ever
/// break between words, so this widget can no longer split one mid-word on
/// its own.
///
/// A single word that genuinely does not fit its column at all still
/// overflows — the same honest "RenderFlex overflowed" signal Flutter gives
/// for any oversized Flex child, rather than the silently wrong-looking
/// mid-word break this replaces. That's deliberate: it is the caller's job
/// to not hand this an impossibly narrow column, exactly as it already is
/// with plain `Text`. The word's `clipBehavior: Clip.hardEdge` keeps an
/// overflow from bleeding into neighbouring UI even so.
class SplitText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Duration baseDelay;
  final Duration charDelay;
  final TextAlign textAlign;

  const SplitText(
    this.text, {
    super.key,
    this.style,
    this.baseDelay = Duration.zero,
    this.charDelay = const Duration(milliseconds: 28),
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;

    // Group into words, each word an atomic Wrap child. Spaces stay as their
    // own (unanimated) children between words, matching the original spacing
    // behaviour.
    final children = <Widget>[];
    var wordChars = <Widget>[];
    var globalIndex = 0;

    void flushWord() {
      if (wordChars.isEmpty) return;
      // Flex directly, not Row: Row does not expose clipBehavior in this
      // SDK. Clipping matters here — an un-clipped Flex that overflows its
      // constraints paints past its bounds (bleeding into neighbouring UI)
      // and shows the yellow/black debug overflow banner, whereas Text
      // overflowing silently clips. A single word that genuinely does not
      // fit its column at all (the caller gave it an unreasonably narrow
      // width) should fail the same quiet way Text does, not loudly.
      children.add(Flex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        clipBehavior: Clip.hardEdge,
        children: wordChars,
      ));
      wordChars = <Widget>[];
    }

    for (final char in text.characters) {
      if (char == ' ') {
        flushWord();
        children.add(Text(' ', style: effectiveStyle));
        globalIndex++;
        continue;
      }
      wordChars.add(
        AppText(char, style: effectiveStyle)
            .animate(delay: baseDelay + charDelay * globalIndex)
            .fadeIn(duration: 200.ms)
            .slideY(
              begin: 0.5,
              end: 0,
              duration: 260.ms,
              curve: Curves.easeOutCubic,
            ),
      );
      globalIndex++;
    }
    flushWord();

    return Wrap(
      alignment: textAlign == TextAlign.center
          ? WrapAlignment.center
          : textAlign == TextAlign.end
              ? WrapAlignment.end
              : WrapAlignment.start,
      children: children,
    );
  }
}
