import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Where the pictures of a chat live between runs: attachment previews and
/// embed images.
///
/// Bounded by how many pictures are kept rather than by the space they take,
/// because the cache manager counts entries and not bytes. That works here
/// because the address they are fetched from already asks the proxy for a
/// resized file, so one entry is tens of kilobytes rather than the original
/// photo, and this many of them land somewhere under half a gigabyte. Discord
/// bounds the same thing the same way: its cache is whatever Chromium keeps,
/// and what it controls is asking for a resized image in the first place.
///
/// The stale period runs from last use, not from download, so a picture goes
/// only once it has been left alone for a fortnight. Losing one costs a single
/// small request the next time it is scrolled past.
final class ChatImageCache extends CacheManager with ImageCacheManager {
  ChatImageCache._(super.config) : _index = config.repo;

  /// Keeps the folder of earlier versions, so a sign-out also clears what they
  /// left there.
  static const _storeKey = 'flucord_attachment_previews';

  static final ChatImageCache instance = ChatImageCache._(
    Config(
      _storeKey,
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 4000,
    ),
  );

  final CacheInfoRepository _index;

  /// Removes every picture from the disk, for a sign-out.
  ///
  /// The index holds the address of each picture and reaches the disk some
  /// seconds after a change. Closing it writes it now, so an app that quits
  /// right after a sign-out leaves no address behind.
  static Future<void> clear() async {
    final cache = instance;
    await cache.emptyCache();
    await cache._index.close();
    await cache._index.open();
  }
}
