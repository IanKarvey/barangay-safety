import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Widest the dashboard's content is allowed to get, shared by the shell and
/// every pushed page so they line up.
///
/// Wide enough that the two-column layouts have room (each column stays around
/// 600px, a comfortable reading width), narrow enough that on a 2560px monitor
/// a line of text is not a kilometre long.
const double kWebContentWidth = 1360;

/// Frames a pushed screen for a desktop browser.
///
/// The screens the dashboard reuses (manage incident, analytics, heat map,
/// notifications...) are full `Scaffold`s written for a phone. Pushed as-is they
/// fill the whole window — on a 1900px monitor the app bar spans the screen and
/// every section stretches edge to edge, which is how the manage-incident page
/// first looked. This centres them at [kWebContentWidth] on a neutral desk
/// colour with a hairline edge, so they read as a page rather than a stretched
/// phone.
///
/// Below [kWebContentWidth] it does nothing visible: the child simply fills the
/// window, so a narrow browser window behaves like the mobile screen.
class WebPageFrame extends StatelessWidget {
  const WebPageFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EDF4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kWebContentWidth),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.divider),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
