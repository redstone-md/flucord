/// Which of the three guild expressions a refusal is about.
enum GuildExpressionKind { emoji, sticker, sound }

/// The guild's expression slots are full, so the upload has nowhere to go.
///
/// Discord counts these per server and per tier. The count is the server's to
/// know, so the refusal arrives from there as a numbered error code that the
/// transport translates into this, and the settings page shows the sentence
/// rather than the code.
final class GuildExpressionLimitReached implements Exception {
  const GuildExpressionLimitReached(this.kind);

  final GuildExpressionKind kind;

  /// One line for the settings page.
  String get message => switch (kind) {
    GuildExpressionKind.emoji => 'This server has no emoji slots left.',
    GuildExpressionKind.sticker => 'This server has no sticker slots left.',
    GuildExpressionKind.sound => 'This server has no sound slots left.',
  };

  @override
  String toString() => message;
}

/// The wire code Discord answers when a guild's slots of [kind] are full.
///
/// Stated beside the exception rather than inside the transports, because it
/// is a protocol fact and protocol facts live in one place.
int guildExpressionLimitCode(GuildExpressionKind kind) => switch (kind) {
  GuildExpressionKind.emoji => 30008,
  GuildExpressionKind.sticker => 30039,
  GuildExpressionKind.sound => 30045,
};
