import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Where the pictures of profile frames and effects live between runs.
///
/// They come from Discord's shop, are the same for every account, and their
/// addresses change whenever their picture does, so a kept copy never goes
/// stale. Discord's client keeps them the same way, in Chromium's cache.
/// They are a few hundred kilobytes each, and a session meets a handful,
/// so the count bounds the folder well under a hundred megabytes.
final class ProfileAssetCache extends CacheManager with ImageCacheManager {
  ProfileAssetCache._(super.config);

  static final ProfileAssetCache instance = ProfileAssetCache._(
    Config(
      'flucord_profile_assets',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 300,
    ),
  );

  /// The picture at [url], from the disk when it was fetched before.
  static ImageProvider image(String url) =>
      CachedNetworkImageProvider(url, cacheManager: instance);
}
