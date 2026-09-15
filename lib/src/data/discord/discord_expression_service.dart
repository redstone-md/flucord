import '../../domain/chat_repository.dart';
import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_expression_errors.dart';
import '../../domain/guild_expression_repository.dart';
import '../../domain/soundboard.dart';
import 'discord_mapper.dart';
import 'discord_multipart_body.dart';
import 'discord_rest_client.dart';
import 'discord_soundboard_service.dart';

/// The expression routes the settings window needs, over one REST session.
abstract interface class DiscordExpressionTransport {
  /// `GET /guilds/{id}/emojis`.
  Future<List<Map<String, Object?>>> listGuildEmojis(String guildId);

  /// `POST /guilds/{id}/emojis`, with the image inline as a data URI.
  Future<Map<String, Object?>> createGuildEmoji(
    String guildId,
    Map<String, Object?> body,
  );

  /// `DELETE /guilds/{id}/emojis/{emojiId}`.
  Future<void> deleteGuildEmoji(String guildId, String emojiId);

  /// `GET /guilds/{id}/stickers`.
  Future<List<Map<String, Object?>>> listGuildStickers(String guildId);

  /// `POST /guilds/{id}/stickers`, a form with the file as one part.
  Future<Map<String, Object?>> createGuildSticker(
    String guildId,
    DiscordMultipartBody body,
  );

  /// `DELETE /guilds/{id}/stickers/{stickerId}`.
  Future<void> deleteGuildSticker(String guildId, String stickerId);

  /// `POST /guilds/{id}/soundboard-sounds`, with the sound inline.
  Future<Map<String, Object?>> createSoundboardSound(
    String guildId,
    Map<String, Object?> body,
  );

  /// `DELETE /guilds/{id}/soundboard-sounds/{soundId}`.
  Future<void> deleteSoundboardSound(String guildId, String soundId);
}

/// Upload and delete for a guild's emoji, stickers and soundboard sounds on
/// the desktop-user session.
///
/// Every mutation folds its answer into the stores the pickers read: the
/// emoji and sticker tables the workspace is restored from, and the
/// soundboard service's own store. The pickers update without a second
/// request, because the repository events and the soundboard's updates
/// stream are what they already listen to.
final class DiscordExpressionService implements GuildExpressionRepository {
  DiscordExpressionService(
    this._transport,
    this._cache,
    this._mapper, {
    DiscordSoundboardService? soundboard,
    this.publish,
  }) : _soundboard = soundboard;

  final DiscordExpressionTransport _transport;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordSoundboardService? _soundboard;

  /// Announces a fresh emoji or sticker set for the guild, as the gateway's
  /// own updates do. This is the event the workspace folds, and what makes a
  /// change made here reach the picker without a reload.
  final void Function(ChatRepositoryEvent event)? publish;

  @override
  Future<List<GuildEmoji>> loadGuildEmojis(String guildId) async {
    final payloads = await _transport.listGuildEmojis(guildId);
    final emojis = [
      for (final payload in payloads) _mapper.emoji(payload, guildId),
    ];
    await _cache.replaceGuildEmojis(guildId, emojis);
    publish?.call(GuildEmojisReplacedEvent(spaceId: guildId, emojis: emojis));
    return emojis;
  }

  @override
  Future<GuildEmoji> uploadGuildEmoji({
    required String guildId,
    required String name,
    required String dataUri,
  }) async {
    final payload = await _guard(
      GuildExpressionKind.emoji,
      () => _transport.createGuildEmoji(guildId, {
        'name': name,
        'image': dataUri,
      }),
    );
    final emoji = _mapper.emoji(payload, guildId);
    await _foldEmoji(guildId, emoji);
    return emoji;
  }

  @override
  Future<void> deleteGuildEmoji({
    required String guildId,
    required String emojiId,
  }) async {
    await _guard(
      GuildExpressionKind.emoji,
      () => _transport.deleteGuildEmoji(guildId, emojiId),
    );
    await _dropEmoji(guildId, emojiId);
  }

  @override
  Future<List<GuildSticker>> loadGuildStickers(String guildId) async {
    final payloads = await _transport.listGuildStickers(guildId);
    final stickers = [
      for (final payload in payloads) _mapper.guildSticker(payload, guildId),
    ];
    await _cache.replaceGuildStickers(guildId, stickers);
    publish?.call(
      GuildStickersReplacedEvent(spaceId: guildId, stickers: stickers),
    );
    return stickers;
  }

  @override
  Future<GuildSticker> uploadGuildSticker({
    required String guildId,
    required String name,
    required String description,
    required String tags,
    required String dataUri,
  }) async {
    final uri = _dataUriOf(dataUri);
    final body = await DiscordMultipartBody.buildForm(
      {'name': name, 'description': description, 'tags': tags},
      [
        // The file part is named for what the bytes are, because Discord
        // stores the sticker's format from the file it reads.
        (
          name: 'file',
          filename: 'sticker${_extensionOf(uri)}',
          bytes: uri.contentAsBytes(),
        ),
      ],
    );
    final payload = await _guard(
      GuildExpressionKind.sticker,
      () => _transport.createGuildSticker(guildId, body),
    );
    final sticker = _mapper.guildSticker(payload, guildId);
    await _foldSticker(guildId, sticker);
    return sticker;
  }

  @override
  Future<void> deleteGuildSticker({
    required String guildId,
    required String stickerId,
  }) async {
    await _guard(
      GuildExpressionKind.sticker,
      () => _transport.deleteGuildSticker(guildId, stickerId),
    );
    await _dropSticker(guildId, stickerId);
  }

  @override
  Future<SoundboardSound> uploadSoundboardSound({
    required String guildId,
    required String name,
    required double volume,
    required String dataUri,
  }) async {
    final payload = await _guard(
      GuildExpressionKind.sound,
      () => _transport.createSoundboardSound(guildId, {
        'name': name,
        'sound': dataUri,
        'volume': volume,
      }),
    );
    final sound = DiscordSoundboardService.readSound(payload, guildId);
    if (sound == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned no soundboard sound',
      );
    }
    _soundboard?.acceptSound(sound);
    return sound;
  }

  @override
  Future<void> deleteSoundboardSound({
    required String guildId,
    required String soundId,
  }) async {
    await _guard(
      GuildExpressionKind.sound,
      () => _transport.deleteSoundboardSound(guildId, soundId),
    );
    _soundboard?.forgetSound(guildId, soundId);
  }

  /// Runs one mutation, translating the numbered refusal a full guild
  /// answers with into the sentence the settings page shows.
  Future<T> _guard<T>(
    GuildExpressionKind kind,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on DiscordApiException catch (error) {
      if (_limitCodeOf(error) == guildExpressionLimitCode(kind)) {
        throw GuildExpressionLimitReached(kind);
      }
      rethrow;
    }
  }

  /// The reason code sits beside the message Discord writes for a person.
  /// Both spellings of the code are read: the bot routes answer with a
  /// number, and the user routes have been seen to answer with its string.
  static int? _limitCodeOf(DiscordApiException error) {
    final code = error.responsePayload?['code'];
    if (code is int) return code;
    if (code is String) return int.tryParse(code);
    return null;
  }

  /// Adds [emoji] to the guild's stored set and announces the new whole set,
  /// the event the workspace folds and the picker reads.
  Future<void> _foldEmoji(String guildId, GuildEmoji emoji) async {
    final held = await _cache.readWorkspace();
    final next = [
      for (final item in held?.emojis ?? const <GuildEmoji>[])
        if (item.spaceId != guildId || item.id != emoji.id) item,
      emoji,
    ];
    await _cache.replaceGuildEmojis(guildId, next);
    publish?.call(GuildEmojisReplacedEvent(spaceId: guildId, emojis: next));
  }

  /// Removes the emoji from the stored set, or leaves the store alone when
  /// the client holds no workspace at all yet.
  Future<void> _dropEmoji(String guildId, String emojiId) async {
    final held = await _cache.readWorkspace();
    if (held == null) return;
    final next = [
      for (final item in held.emojis)
        if (item.spaceId != guildId || item.id != emojiId) item,
    ];
    await _cache.replaceGuildEmojis(guildId, next);
    publish?.call(GuildEmojisReplacedEvent(spaceId: guildId, emojis: next));
  }

  Future<void> _foldSticker(String guildId, GuildSticker sticker) async {
    final held = await _cache.readWorkspace();
    final next = [
      for (final item in held?.stickers ?? const <GuildSticker>[])
        if (item.spaceId != guildId || item.id != sticker.id) item,
      sticker,
    ];
    await _cache.replaceGuildStickers(guildId, next);
    publish?.call(GuildStickersReplacedEvent(spaceId: guildId, stickers: next));
  }

  Future<void> _dropSticker(String guildId, String stickerId) async {
    final held = await _cache.readWorkspace();
    if (held == null) return;
    final next = [
      for (final item in held.stickers)
        if (item.spaceId != guildId || item.id != stickerId) item,
    ];
    await _cache.replaceGuildStickers(guildId, next);
    publish?.call(GuildStickersReplacedEvent(spaceId: guildId, stickers: next));
  }

  /// Parses a `data:` URI, for the one route that takes a file part rather
  /// than an inline image.
  static UriData _dataUriOf(String dataUri) {
    final uri = Uri.tryParse(dataUri);
    if (uri == null || uri.scheme != 'data' || uri.data == null) {
      throw ArgumentError.value(dataUri, 'dataUri', 'Expected a data: URI');
    }
    return uri.data!;
  }

  static String _extensionOf(UriData data) => switch (data.mimeType) {
    'image/gif' => '.gif',
    'application/json' => '.json',
    _ => '.png',
  };
}
