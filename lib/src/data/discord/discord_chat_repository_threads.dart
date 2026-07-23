part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryThreads on DiscordChatRepository {
  Future<ConversationChannel> _createMessageThread({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final workspace = await _cache.readWorkspace();
    final parent = workspace?.channelOrNull(channelId);
    if (parent == null) throw StateError('Parent channel is not cached');
    final payload = await _api.createThreadFromMessage(
      channelId: channelId,
      messageId: messageId,
      name: name,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    );
    final thread = _mapThread(payload, parent.spaceId);
    await _cache.writeChannel(thread);
    return thread;
  }

  Future<ArchivedThreadPage> _loadArchivedThreads(
    String parentChannelId, {
    DateTime? before,
  }) async {
    final workspace = await _cache.readWorkspace();
    final parent = workspace?.channelOrNull(parentChannelId);
    if (parent == null) throw StateError('Parent channel is not cached');
    final payload = await _api.getPublicArchivedThreads(
      parentChannelId,
      before: before,
    );
    final threads = (payload['threads'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => _mapThread(raw.cast<String, Object?>(), parent.spaceId))
        .toList(growable: false);
    for (final thread in threads) {
      await _cache.writeChannel(thread);
    }
    final requestedMore = payload['has_more'] == true;
    final nextBefore = threads.lastOrNull?.archiveTimestamp;
    return ArchivedThreadPage(
      threads: threads,
      hasMore: requestedMore && nextBefore != null,
      nextBefore: nextBefore,
    );
  }

  ConversationChannel _mapThread(
    Map<String, Object?> payload,
    String fallbackGuildId,
  ) {
    final guildId = payload['guild_id'] as String? ?? fallbackGuildId;
    final thread = _mapper.channel(payload, guildId);
    if (thread == null || !thread.isThread) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a Discord thread channel',
      );
    }
    return thread;
  }
}
