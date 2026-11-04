import '../../domain/chat_models.dart';

final class DiscordCdn {
  const DiscordCdn._();

  static const _validSizes = {16, 32, 64, 128, 256, 512, 1024, 2048, 4096};

  static String? guildIcon(String guildId, String? hash, {int size = 128}) =>
      _asset(['icons', guildId], hash, size: size);

  static String? guildBanner(String guildId, String? hash, {int size = 512}) =>
      _asset(['banners', guildId], hash, size: size);

  /// A group DM's own picture.
  static String? channelIcon(
    String channelId,
    String? hash, {
    int size = 128,
  }) => _asset(['channel-icons', channelId], hash, size: size);

  static String? userAvatar(String userId, String? hash, {int size = 128}) =>
      hash == null || hash.isEmpty
      ? defaultUserAvatar(userId)
      : _asset(['avatars', userId], hash, size: size);

  static String? userBanner(String userId, String? hash, {int size = 512}) =>
      _asset(['banners', userId], hash, size: size);

  /// An application's icon, as an invite's page shows it.
  static String? appIcon(
    String applicationId,
    String? hash, {
    int size = 128,
  }) => _asset(['app-icons', applicationId], hash, size: size);

  /// The small badge of a server's tag, drawn beside a member's name.
  static String? clanBadge(String guildId, String? hash, {int size = 32}) =>
      _asset(['clan-badges', guildId], hash, size: size);

  /// A profile badge's icon, by the hash the profile route gives with it.
  static String? badgeIcon(String icon) =>
      _named(icon, '/badge-icons/$icon.png');

  /// The avatar decoration somebody wears. `passthrough` keeps an animated
  /// one moving.
  static String? avatarDecoration(String asset, {int size = 96}) => _named(
    asset,
    '/avatar-decoration-presets/$asset.png',
    {'size': '$size', 'passthrough': 'true'},
  );

  /// The still picture of a nameplate, by its `asset` path, which ends in a
  /// slash.
  ///
  /// Discord's image reference does not list it. The path is
  /// `/assets/collectibles/{asset}static.png` in the reverse-engineered client
  /// docs (discord-userdoccers, reference.mdx "CDN Formatting": valid names
  /// are `img.png`, `static.png` and `asset.webm`, and `size` is ignored) and
  /// in two maintained libraries: Pycord's `Asset._from_collectible` and
  /// Kord's `DiscordCdn.staticNameplate`.
  static String? nameplate(String asset) => _collectible(asset, 'static.png');

  /// The moving nameplate, `asset.webm` beside the still picture (the same
  /// sources as [nameplate]).
  static String? movingNameplate(String asset) =>
      _collectible(asset, 'asset.webm');

  static String? _collectible(String asset, String file) => _named(
    asset,
    '/assets/collectibles/${asset.endsWith('/') ? asset : '$asset/'}$file',
  );

  /// [path] on the CDN, or null when [name], the part of it that names the
  /// file, is empty.
  static String? _named(
    String name,
    String path, [
    Map<String, String>? query,
  ]) => name.isEmpty
      ? null
      : Uri.https('cdn.discordapp.com', path, query).toString();

  static String? guildMemberAvatar(
    String guildId,
    String userId,
    String? hash, {
    int size = 128,
  }) =>
      _asset(['guilds', guildId, 'users', userId, 'avatars'], hash, size: size);

  /// The banner somebody set for one server.
  static String? guildMemberBanner(
    String guildId,
    String userId,
    String? hash, {
    int size = 512,
  }) =>
      _asset(['guilds', guildId, 'users', userId, 'banners'], hash, size: size);

  static String customEmoji(
    String emojiId, {
    bool animated = false,
    int size = 32,
  }) {
    if (!_validSizes.contains(size)) {
      throw ArgumentError.value(
        size,
        'size',
        'must be a power of two, 16-4096',
      );
    }
    return Uri.https(
      'cdn.discordapp.com',
      '/emojis/$emojiId.${animated ? 'gif' : 'webp'}',
      {'size': '$size', 'quality': 'lossless'},
    ).toString();
  }

  static String sticker(String stickerId, StickerFormat format) {
    final extension = switch (format) {
      StickerFormat.lottie => 'json',
      StickerFormat.gif => 'gif',
      _ => 'png',
    };
    return Uri.https(
      'cdn.discordapp.com',
      '/stickers/$stickerId.$extension',
    ).toString();
  }

  /// The artwork behind an `activity.assets.*_image` key.
  ///
  /// Three forms reach this field and only three are honoured. `mp:` is
  /// Discord's media proxy and carries the rest of the path; `spotify:` names
  /// an image on Spotify's own CDN; anything else is an application asset hash
  /// that is only addressable together with the application it belongs to. A
  /// prefix this client does not recognise returns null rather than being
  /// pasted into a URL, because a guessed host would leak the fact that this
  /// user is being looked at to whoever owns it.
  static String? activityAsset(
    String? key, {
    String? applicationId,
    int size = 128,
  }) {
    if (key == null || key.isEmpty) return null;
    if (key.startsWith('mp:')) {
      final path = key.substring(3);
      return path.isEmpty
          ? null
          : Uri.https('media.discordapp.net', '/$path').toString();
    }
    if (key.startsWith('spotify:')) {
      final id = key.substring(8);
      return id.isEmpty
          ? null
          : Uri.https('i.scdn.co', '/image/$id').toString();
    }
    if (key.contains(':') || applicationId == null || applicationId.isEmpty) {
      return null;
    }
    if (!_validSizes.contains(size)) {
      throw ArgumentError.value(
        size,
        'size',
        'must be a power of two, 16-4096',
      );
    }
    return Uri.https(
      'cdn.discordapp.com',
      '/app-assets/$applicationId/$key.png',
      {'size': '$size'},
    ).toString();
  }

  static String? defaultUserAvatar(String userId) {
    final snowflake = BigInt.tryParse(userId);
    if (snowflake == null) return null;
    final index = (snowflake >> 22).remainder(BigInt.from(6));
    return Uri.https(
      'cdn.discordapp.com',
      '/embed/avatars/$index.png',
    ).toString();
  }

  static String? _asset(List<String> path, String? hash, {required int size}) {
    if (hash == null || hash.isEmpty) return null;
    if (!_validSizes.contains(size)) {
      throw ArgumentError.value(
        size,
        'size',
        'must be a power of two, 16-4096',
      );
    }
    final format = hash.startsWith('a_') ? 'gif' : 'webp';
    return Uri.https(
      'cdn.discordapp.com',
      '/${[...path, '$hash.$format'].join('/')}',
      {'size': '$size'},
    ).toString();
  }
}
