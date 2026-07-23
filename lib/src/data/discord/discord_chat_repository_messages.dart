part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryMessages on DiscordChatRepository {
  Future<void> _handleMessageDispatch(DiscordGatewayDispatch event) async {
    final messageId = event.data['id'] as String?;
    if (messageId == null) return;
    final currentUserId = _currentMemberId;
    if (event.name == 'MESSAGE_CREATE' && currentUserId != null) {
      final conversation = await _directMessages.acceptMessage(
        event.data,
        currentUserId,
      );
      if (conversation != null) _emitDirectConversation(conversation);
    }
    final fallback = event.name == 'MESSAGE_UPDATE'
        ? await _cache.readMessage(messageId)
        : null;
    if (event.name == 'MESSAGE_UPDATE' && fallback == null) return;
    final message = _mapper.message(
      event.data,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
    final authorPayload = event.data['author'];
    final member = authorPayload is Map
        ? _mapper.member(
            authorPayload.cast<String, Object?>(),
            spaceIds: {
              if (event.data['guild_id'] case final String guildId) guildId,
              if (event.data['guild_id'] == null)
                DiscordMapper.directMessagesSpaceId,
            },
          )
        : null;
    await _cache.writeMessage(message, member: member);
    if (_events.isClosed) return;
    _events.add(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: event.name == 'MESSAGE_CREATE',
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
  }

  void _emitDirectConversation(DirectConversation conversation) {
    if (_events.isClosed) return;
    _events.add(SpaceUpsertedEvent(_directMessages.space));
    _events.add(MemberUpsertedEvent(conversation.recipient));
    _events.add(ChannelUpsertedEvent(conversation.channel));
  }
}
