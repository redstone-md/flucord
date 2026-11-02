part of 'chat_controller.dart';

extension _ChatControllerEvents on ChatController {
  void _listenToRepository() {
    _eventSubscription = _repository.events.listen(_handleEvent);
    _listenToConversationSummaries();
    _listenToReadState();
  }

  /// Folds [event] in, and notifies only if that changed something.
  ///
  /// A fold that changes nothing hands back the same workspace, so comparing the
  /// instance answers for the workspace. [changedElsewhere] answers for the state
  /// the controller holds outside it.
  void _handleEvent(ChatRepositoryEvent event) {
    final workspaceBefore = _workspace;
    var changedElsewhere = false;
    switch (event) {
      case MessageUpsertedEvent():
        _handleMessageUpsert(event);
      case MessageUpdatedEvent(:final messageId, :final applyTo, :final member):
        _workspace = _workspace?.updateMessage(messageId, applyTo);
        if (member != null) _workspace = _workspace?.upsertMember(member);
      case MessageReactionChangedEvent(:final change):
        _workspace = _workspace?.updateMessage(
          change.messageId,
          change.applyTo,
        );
      case MessageDeletedEvent():
        _workspace = _workspace?.removeMessage(event.messageId);
      case MessagesDeletedEvent():
        _workspace = _workspace?.removeMessages(event.messageIds);
      case ChannelUpsertedEvent():
        _workspace = _workspace?.upsertChannel(event.channel);
      case CategoryUpsertedEvent():
        _workspace = _workspace?.upsertCategory(event.category);
      case SpaceUpsertedEvent():
        _workspace = _workspace?.upsertSpace(event.space);
      case GuildGainedEvent():
        _workspace = _workspace?.mergeGuild(event.guild);
        _applyReadState();
      case SpaceRemovedEvent():
        _workspace = _workspace?.removeGuild(event.spaceId);
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
        changedElsewhere = true;
      case GuildScheduledEventDeletedEvent():
        _deleteScheduledEvent(event.spaceId, event.eventId);
        changedElsewhere = true;
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
        // Discord streams presence for people the member table has never
        // heard of, so this is a routine event that must cost nothing.
        if (_workspace?.memberOrNull(event.memberId) != null) {
          _workspace = _workspace?.applyPresence(
            event.memberId,
            event.presence,
          );
        }
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
        changedElsewhere = _restoreChannelHistory(event);
      case RepositoryStatusChangedEvent():
        changedElsewhere = _connectionStatus != event.status;
        _connectionStatus = event.status;
    }
    if (changedElsewhere || !identical(_workspace, workspaceBefore)) _notify();
  }

  /// Announces the summaries store moving, so the strip above the timeline
  /// redraws without folding anything into the workspace.
  ///
  /// Summaries are channel-scoped data the store already holds, so a
  /// change is announced rather than copied: nothing else in the workspace
  /// reads them, and the strip asks for what it draws.
  void _listenToConversationSummaries() {
    final repository = _repository.conversationSummaries;
    if (repository == null) return;
    _conversationSummarySubscription = repository.updates.listen((_) {
      _notify();
    });
  }

  /// Folds the server's read state into the workspace as it arrives.
  ///
  /// The rail pips, the NEW divider and the Inbox all read the channel's own
  /// unread fields, so this is the single point where the server replaces what
  /// the client guessed — and the only one, which is what keeps the two from
  /// disagreeing.
  ///
  /// An update that moves no channel and no setting notifies nobody. The server
  /// echoes each ack this client sends, so this is common.
  void _listenToReadState() {
    final repository = _repository.readState;
    if (repository == null) return;
    var previous = repository.current;
    _readStateSubscription = repository.updates.listen((snapshot) {
      final settingsChanged = !snapshot.sameSettingsAs(previous);
      previous = snapshot;
      final workspaceBefore = _workspace;
      _applyReadState();
      if (settingsChanged || !identical(_workspace, workspaceBefore)) _notify();
    });
  }

  void _applyReadState() {
    final snapshot = _repository.readState?.current;
    if (snapshot == null) return;
    _workspace = _workspace
        ?.applyReadState(snapshot)
        .clearReadBoundaries(activeChannelId: _activeChannelId);
  }

  void _handleMessageUpsert(MessageUpsertedEvent event) {
    final message = event.mentionsCurrentMember
        ? event.message.copyWith(mentionsCurrentMember: true)
        : event.message;
    final isOwn = message.authorId == _workspace?.currentMemberId;
    _workspace = _workspace?.upsertMessage(message, member: event.member);
    _capChannelIfNotOpen(message.channelId);
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
    if (_boundaryAwaitsNewMessage && message.channelId == _activeChannelId) {
      _boundaryAwaitsNewMessage = false;
      _workspace = _workspace?.clearChannelUnreadBoundary(message.channelId);
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
