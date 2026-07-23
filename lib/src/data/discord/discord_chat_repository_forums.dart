part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryForums on DiscordChatRepository {
  Future<CreatedForumPost> _createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    required List<PendingAttachment> attachments,
    required List<String> appliedTagIds,
  }) async {
    final workspace = await _cache.readWorkspace();
    final parent = workspace?.channelOrNull(channelId);
    if (parent == null ||
        (parent.kind != ChannelKind.forum &&
            parent.kind != ChannelKind.media)) {
      throw StateError('Forum or media channel is not cached');
    }
    final payload = await _api.createForumPost(
      channelId: channelId,
      name: name,
      content: content,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
      attachments: attachments,
      appliedTagIds: appliedTagIds,
    );
    final thread = _mapThread(payload, parent.spaceId);
    final rawMessage = payload['message'];
    if (rawMessage is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a Discord forum starter message',
      );
    }
    final messagePayload = rawMessage.cast<String, Object?>();
    final message = _mapper.message(
      messagePayload,
      currentMemberId: _currentMemberId,
    );
    await _cache.writeChannel(thread);
    await _cache.writeMessage(message);
    return CreatedForumPost(thread: thread, initialMessage: message);
  }
}
