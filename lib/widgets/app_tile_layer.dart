import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_config.dart';

/// Caches map tiles to disk via `cached_network_image`'s cache manager, so
/// panning back over ground already seen costs nothing.
class CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}

/// The app's one and only map tile layer.
///
/// Every map must use this rather than building its own [TileLayer] — it is
/// what guarantees the provider URL and disk caching stay consistent. Before
/// this existed the tile URL was copy-pasted into 10 places, half of them
/// without caching.
///
/// Attribution ([AppConfig.mapAttribution]) is required by Stadia's terms
/// wherever these tiles are shown.
class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: AppConfig.mapTileUrl,
      userAgentPackageName: 'com.barangaysafety.app',
      tileProvider: CachedTileProvider(),
      // Stadia serves 512px tiles for these styles; letting flutter_map know
      // keeps labels crisp instead of upscaled.
      maxNativeZoom: 20,
    );
  }
}
