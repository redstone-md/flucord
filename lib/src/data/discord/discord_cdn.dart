final class DiscordCdn {
  const DiscordCdn._();

  static const _validSizes = {16, 32, 64, 128, 256, 512, 1024, 2048, 4096};

  static String? guildIcon(String guildId, String? hash, {int size = 128}) =>
      _asset(['icons', guildId], hash, size: size);

  static String? userAvatar(String userId, String? hash, {int size = 128}) =>
      hash == null || hash.isEmpty
      ? defaultUserAvatar(userId)
      : _asset(['avatars', userId], hash, size: size);

  static String? guildMemberAvatar(
    String guildId,
    String userId,
    String? hash, {
    int size = 128,
  }) =>
      _asset(['guilds', guildId, 'users', userId, 'avatars'], hash, size: size);

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
