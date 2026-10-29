import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:barangay_safety_app/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders real widgets to PNG files from a test, with real fonts.
///
/// Flutter tests draw every glyph as a solid box (the "Ahem" font), which makes
/// a screenshot useless for judging a layout. The Flutter SDK ships Roboto and
/// the Material icon font, so this loads them. The app names 'Poppins' in its
/// text styles but never bundles it, so on a device it falls back to Roboto;
/// loading Roboto under that name here reproduces what is actually on screen.
///
/// Output goes to [renderDir]. Nothing here changes what a test asserts — it
/// exists so a person can look at the result.
const _fontDir = 'C:/flutter/bin/cache/artifacts/material_fonts';

/// Where PNGs are written. Override with RENDER_DIR to keep them elsewhere.
String get renderDir =>
    Platform.environment['RENDER_DIR'] ??
    '${Directory.systemTemp.path}/barangay_renders';

Future<void> loadRealFonts() async {
  Future<ByteData> bytes(String file) async {
    final data = await File('$_fontDir/$file').readAsBytes();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(bytes(f));
    }
    await loader.load();
  }

  const roboto = ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'];
  await family('Roboto', roboto);
  await family('Poppins', roboto);
  await family('MaterialIcons', ['materialicons-regular.otf']);
}

final _snapKey = GlobalKey();

/// The boundary [snap] captures, for tests that build their own app shell (to set
/// a language or a font scale) instead of using [renderApp].
final GlobalKey snapKey = _snapKey;

/// Wraps [child] in the app's theme, strings and providers, ready to render.
///
/// [extraProviders] lets a test supply the fake providers a screen reads.
Widget renderApp(
  Widget child, {
  List<SingleChildWidget> extraProviders = const [],
  List<RouteSettings>? routeLog,
}) {
  SharedPreferences.setMockInitialValues({});
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ...extraProviders,
    ],
    child: Consumer<LanguageProvider>(
      builder: (context, lang, _) => AppStringsScope(
        language: lang.language,
        strings: lang.strings,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          // When a test passes [routeLog], every named route pushed from the
          // screen is recorded there and answered with a stub page.
          onGenerateRoute: routeLog == null
              ? null
              : (settings) {
                  routeLog.add(settings);
                  return MaterialPageRoute(
                    settings: settings,
                    builder: (_) => const Scaffold(body: Text('PUSHED PAGE')),
                  );
                },
          home: Scaffold(
            body: RepaintBoundary(key: _snapKey, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Sets the test window to [size] logical pixels at 1x.
void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Writes whatever [renderApp] is showing to `<renderDir>/<name>.png`.
Future<String> snap(WidgetTester tester, String name) async {
  final path = '$renderDir/$name.png';
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_snapKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(renderDir).create(recursive: true);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
  });
  return path;
}
