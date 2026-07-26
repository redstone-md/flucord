part of 'chat_controller.dart';

extension _ChatControllerEvents on ChatController {
  void _listenToRepository() {
    _eventSubscription = _repository.events.listen((event) {
      switch (event) {
        case MessageUpsertedEvent():
          _handleMessageUpsert(event);
        case MessageDeletedEvent():
          _workspace = _workspace?.removeMessage(event.messageId);
        case ChannelUpsertedEvent():
          _workspace = _workspace?.upsertChannel(event.channel);
        case CategoryUpsertedEvent():
          _workspace = _workspace?.upsertCategory(event.category);
        case SpaceUpsertedEvent():
          _workspace = _workspace?.upsertSpace(event.space);
        case GuildEmojisReplacedEvent():
          _workspace = _workspace?.replaceGuildEmojis(
            event.spaceId,
            event.emojis,
          );
        case GuildStickersReplacedEvent():
          _workspace = _workspace?.replaceGuildStickers(
            event.spaceId,
            event.stickers,
          );
        case GuildScheduledEventUpsertedEvent():
          _upsertScheduledEvent(event.event);
        case GuildScheduledEventDeletedEvent():
          _deleteScheduledEvent(event.spaceId, event.eventId);
        case ChannelDeletedEvent():
          _workspace = _workspace?.removeChannel(event.channelId);
        case CategoryDeletedEvent():
          _workspace = _workspace?.removeCategory(event.categoryId);
        case MemberUpsertedEvent():
          _workspace = _workspace?.upsertMember(event.member);
        case MembersUpsertedEvent():
          _workspace = _workspace?.upsertMembers(event.members);
        case MemberRemovedEvent():
          _workspace = _workspace?.removeMemberFromSpace(
            event.memberId,
            event.spaceId,
          );
        case PresenceChangedEvent():
          _workspace = _workspace?.updatePresence(
            event.memberId,
            event.presence,
          );
        case TypingStartedEvent():
          _handleTyping(event);
        case PinsChangedEvent():
          if (_pinnedMessages.containsKey(event.channelId)) {
            unawaited(loadPinnedMessages(event.channelId, refresh: true));
          }
        case RepositoryStatusChangedEvent():
          _connectionStatus = event.status;
      }
      _notify();
    });
  }

  void _handleMessageUpsert(MessageUpsertedEvent event) {
    final message = event.mentionsCurrentMember
        ? event.message.copyWith(mentionsCurrentMember: true)
        : event.message;
    _workspace = _workspace?.upsertMessage(message, member: event.member);
    if (!event.isNew || message.authorId == _workspace?.currentMemberId) return;
    _incomingMessages.add(event);
    if (_isApplicationActive && message.channelId == _activeChannelId) return;
    _workspace = _workspace?.markChannelUnread(
      message.channelId,
      messageId: message.id,
      mention: message.mentionsCurrentMember,
    );
    _persistChannelActivity(message.channelId);
  }

  void _handleTyping(TypingStartedEvent event) {
    if (event.memberId == _workspace?.currentMemberId) return;
    final members = _typingMembers.putIfAbsent(event.channelId, () => {});
    members.add(event.memberId);
    final key = '${event.channelId}:${event.memberId}';
    _typingTimers[key]?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 9), () {
      _typingMembers[event.channelId]?.remove(event.memberId);
      _typingTimers.remove(key);
      if (!_disposed) _notify();
    });
  }
}
