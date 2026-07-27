import '../../domain/chat_models.dart';

final class DiscordCdn {
  const DiscordCdn._();

  static const _validSizes = {16, 32, 64, 128, 256, 512, 1024, 2048, 4096};

  static String? guildIcon(String guildId, String? hash, {int size = 128}) =>
      _asset(['icons', guildId], hash, size: size);

  static String? guildBanner(String guildId, String? hash, {int size = 512}) =>
      _asset(['banners', guildId], hash, size: size);

  static String? userAvatar(String userId, String? hash, {int size = 128}) =>
      hash == null || hash.isEmpty
      ? defaultUserAvatar(userId)
      : _asset(['avatars', userId], hash, size: size);

  static String? userBanner(String userId, String? hash, {int size = 512}) =>
      _asset(['banners', userId], hash, size: size);

  static String? guildMemberAvatar(
    String guildId,
    String userId,
    String? hash, {
    int size = 128,
  }) =>
      _asset(['guilds', guildId, 'users', userId, 'avatars'], hash, size: size);

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
