import 'chat_models.dart';
import 'soundboard.dart';

/// Upload and delete for a guild's emoji, stickers and soundboard sounds.
///
/// One contract for the three kinds because the surface is one page: Discord
/// groups them under the same permission and answers them with the same
/// numbered refusals, and the settings window edits them side by side. The
/// guild-management contract stays out of it on purpose: expressions are the
/// account's shared vocabulary, and the pickers read them through the
/// workspace and the soundboard store rather than through the settings
/// window.
///
/// Every method folds its answer into the stores the pickers read before it
/// returns, so a change made here is visible in the composer at once: the
/// emoji and sticker tables the workspace is restored from, and the
/// soundboard service's own store.
///
/// Nothing here checks a permission. That judgement needs the workspace and
/// belongs to `WorkspacePermissions`; the settings page answers it before it
/// asks, the same way every other guild write does.
abstract interface class GuildExpressionRepository {
  /// Reads the guild's emoji, and files the set into the local store.
  ///
  /// The read is the settings page's list; the fold is what lets the picker
  /// show the set without asking again.
  Future<List<GuildEmoji>> loadGuildEmojis(String guildId);

  /// Adds one emoji, from a `data:` URI of a PNG, JPEG, GIF or WebP image.
  ///
  /// The image travels inline the way an avatar edit does, which is the form
  /// this route takes. The answer is the created emoji.
  Future<GuildEmoji> uploadGuildEmoji({
    required String guildId,
    required String name,
    required String dataUri,
  });

  /// Removes one emoji from the guild and from the local stores.
  Future<void> deleteGuildEmoji({
    required String guildId,
    required String emojiId,
  });

  /// Reads the guild's stickers, and files the set into the local store.
  Future<List<GuildSticker>> loadGuildStickers(String guildId);

  /// Adds one sticker from a `data:` URI of a PNG, APNG, GIF or Lottie file.
  ///
  /// [tags] is the name of a unicode emoji that suits the sticker, which is
  /// the form Discord's own client files it under. The route takes a
  /// multipart file part, so the transport decodes the data URI back to
  /// bytes; the inline form is what the file picker produces either way.
  Future<GuildSticker> uploadGuildSticker({
    required String guildId,
    required String name,
    required String description,
    required String tags,
    required String dataUri,
  });

  /// Removes one sticker from the guild and from the local stores.
  Future<void> deleteGuildSticker({
    required String guildId,
    required String stickerId,
  });

  /// Adds one soundboard sound from a `data:` URI of an MP3 or OGG file.
  ///
  /// [volume] is `0` to `1`, the form the server stores and the picker plays.
  Future<SoundboardSound> uploadSoundboardSound({
    required String guildId,
    required String name,
    required double volume,
    required String dataUri,
  });

  /// Removes one sound from the guild and from the local stores.
  Future<void> deleteSoundboardSound({
    required String guildId,
    required String soundId,
  });
}
