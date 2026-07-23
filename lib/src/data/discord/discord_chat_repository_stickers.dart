part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryStickers implements StickerRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  String? get _currentMemberId;
  StreamController<ChatRepositoryEvent> get _events;

  @override
  Future<ChatMessage> sendStickers({
    required String channelId,
    required String authorId,
    required List<String> stickerIds,
  }) async {
    if (stickerIds.isEmpty || stickerIds.length > 3) {
      throw ArgumentError.value(stickerIds, 'stickerIds', 'must contain 1-3');
    }
    final payload = await _api.createMessage(
      channelId: channelId,
      content: '',
      stickerIds: stickerIds,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    await _cache.writeMessage(message);
    return message;
  }

  Future<void> _handleGuildStickers(Map<String, Object?> data) async {
    final guildId = (data['guild_id'] ?? data['id']) as String?;
    final rawStickers = data['stickers'];
    if (guildId == null || rawStickers is! List) return;
    final stickers = rawStickers
        .whereType<Map>()
        .map(
          (payload) =>
              _mapper.guildSticker(payload.cast<String, Object?>(), guildId),
        )
        .toList(growable: false);
    await _cache.replaceGuildStickers(guildId, stickers);
    if (_events.isClosed) return;
    _events.add(
      GuildStickersReplacedEvent(spaceId: guildId, stickers: stickers),
    );
  }
}
