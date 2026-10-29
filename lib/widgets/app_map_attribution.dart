import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../config/app_config.dart';

/// Tile-provider credit, required wherever Stadia tiles are drawn.
///
/// Stadia's terms of service oblige us to credit Stadia Maps, OpenMapTiles and
/// OpenStreetMap contributors on every map that displays their tiles — not once
/// in an About page. `AppConfig.mapAttribution` has held the string since the
/// tile layer was centralised, but nothing rendered it, so the app was in
/// breach on all twelve maps.
///
/// Rendered as a collapsed "i" badge rather than a permanent text bar: the
/// obligation is that the credit is *available* on the map, and a text strip
/// across a live incident map would cover the thing an official is trying to
/// look at.
class AppMapAttribution extends StatelessWidget {
  const AppMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return const RichAttributionWidget(
      alignment: AttributionAlignment.bottomRight,
      // Never auto-expand: on the emergency screens this sits on top of the
      // reporter's own location marker.
      popupInitialDisplayDuration: Duration.zero,
      attributions: [
        TextSourceAttribution(AppConfig.mapAttribution),
      ],
    );
  }
}
