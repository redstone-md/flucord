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
          _workspace = _workspace?.applyPresence(
            event.memberId,
            event.presence,
          );
        case PresencesChangedEvent():
          _workspace = _workspace?.applyPresences(event.presences);
        case TypingStartedEvent():
          _handleTyping(event);
        case PinsChangedEvent():
          if (_pinnedMessages.containsKey(event.channelId)) {
            unawaited(loadPinnedMessages(event.channelId, refresh: true));
          }
        case ChannelLastMessageEvent():
          _workspace = _workspace?.recordLatestMessage(
            event.channelId,
            event.messageId,
          );
          _applyReadState();
        case ChannelHistoryRestoredEvent():
          _restoreChannelHistory(event);
        case RepositoryStatusChangedEvent():
          _connectionStatus = event.status;
      }
      _notify();
    });
    _listenToReadState();
  }

  /// Folds the server's read state into the workspace as it arrives.
  ///
  /// The rail pips, the NEW divider and the Inbox all read the channel's own
  /// unread fields, so this is the single point where the server replaces what
  /// the client guessed — and the only one, which is what keeps the two from
  /// disagreeing.
  void _listenToReadState() {
    final repository = _repository.readState;
    if (repository == null) return;
    _readStateSubscription = repository.updates.listen((_) {
      _applyReadState();
      _notify();
    });
  }

  void _applyReadState() {
    final snapshot = _repository.readState?.current;
    if (snapshot == null) return;
    _workspace = _workspace?.applyReadState(snapshot);
  }

  void _handleMessageUpsert(MessageUpsertedEvent event) {
    final message = event.mentionsCurrentMember
        ? event.message.copyWith(mentionsCurrentMember: true)
        : event.message;
    final isOwn = message.authorId == _workspace?.currentMemberId;
    _workspace = _workspace?.upsertMessage(message, member: event.member);
    if (isOwn) {
      // Sending a message reads the channel. Advancing the latest-message
      // pointer without advancing the ack cursor would leave the sender
      // looking at their own message as an unread one.
      _workspace = _workspace?.markChannelRead(message.channelId);
    }
    if (!event.isNew || isOwn) return;
    _incomingMessages.add(event);
    if (_isApplicationActive && message.channelId == _activeChannelId) {
      // R04's ACK_INCOMING_MESSAGE trigger: a message that lands in the channel
      // the user is looking at is read the moment it arrives.
      acknowledgeChannel(message.channelId);
      return;
    }
    // The local mark stays: it is the whole unread model on a transport with no
    // read state, and on one that has read state the projection below simply
    // overwrites it with the server's answer a moment later.
    _workspace = _workspace?.markChannelUnread(
      message.channelId,
      messageId: message.id,
      mention: message.mentionsCurrentMember,
    );
    _applyReadState();
    _persistChannelActivity(message.channelId);
  }
}
