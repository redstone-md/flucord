part of 'chat_controller.dart';

/// The server-owned unread surface of whatever transport is connected.
///
/// Kept as an extension for the same reason as the settings surface: the
/// answer has to follow the live repository, because a bot session has no read
/// state at all and swapping transports must not leave the shell acking
/// against an account nobody is signed into.
extension ChatControllerReadState on ChatController {
  /// The read-state store of the active transport, or `null` when it has none.
  ReadStateRepository? get readStateRepository => _repository.readState;

  /// What the server says about unread and notification settings right now.
  ReadStateSnapshot get readState =>
      _repository.readState?.current ?? ReadStateSnapshot.empty;

  bool isChannelMuted(ConversationChannel channel) =>
      readState.isChannelMuted(channel);

  bool isSpaceMuted(String spaceId) => readState.isSpaceMuted(spaceId);

  /// Whether [channel] should show an unread pip at all.
  ///
  /// R04 resolves this from the notification settings, not from the read state:
  /// a channel set to "only mentions" is unread to the server and silent in the
  /// sidebar, which is the whole point of the setting.
  bool showsUnreadFor(ConversationChannel channel) {
    if (channel.mentionCount > 0) return true;
    if (!channel.unread) return false;
    return readState.unreadBadgeFor(channel) == UnreadBadge.allMessages;
  }

  /// Acknowledges [channelId] up to the newest message the client knows of.
  ///
  /// Silent when the transport has no read state, when the channel has no
  /// messages, or when `VIEW_CHANNEL` is not held — R04 refuses to track
  /// unreads for a channel the account cannot read, and acking one would be a
  /// request the server rejects.
  void acknowledgeChannel(String channelId, {bool immediate = false}) {
    final repository = _repository.readState;
    final workspace = _workspace;
    if (repository == null || workspace == null) return;
    final channel = workspace.channelOrNull(channelId);
    final messageId = channel?.lastMessageId;
    if (channel == null || messageId == null) return;
    if (!WorkspacePermissions(
      workspace,
    ).can(DiscordPermissions.viewChannel, channel)) {
      return;
    }
    unawaited(
      repository
          .acknowledge(channel, messageId: messageId, immediate: immediate)
          .catchError(_absorbReadStateFailure),
    );
  }

  /// Rewinds [message]'s channel so everything from it onward is unread again.
  Future<void> markChannelUnreadFrom(ChatMessage message) async {
    final repository = _repository.readState;
    final workspace = _workspace;
    final channel = workspace?.channelOrNull(message.channelId);
    if (repository == null || workspace == null || channel == null) return;
    // R04: the ack id is the newest cached message strictly older than the one
    // the user picked, because the cursor names the last message *read*.
    final previous = workspace
        .messagesFor(channel.id)
        .where((item) => item.sentAt.isBefore(message.sentAt))
        .lastOrNull;
    final mentionCount = workspace
        .messagesFor(channel.id)
        .where(
          (item) =>
              !item.sentAt.isBefore(message.sentAt) &&
              item.mentionsCurrentMember,
        )
        .length;
    await repository
        .markUnread(
          channel,
          messageId:
              previous?.id ??
              DiscordSnowflake.fromTimestampMillis(
                message.sentAt.millisecondsSinceEpoch - 1,
              ),
          mentionCount: mentionCount,
        )
        .catchError(_absorbReadStateFailure);
    _notify();
  }

  /// Clears every unread marker the account is carrying.
  ///
  /// The local pass happens first so the sidebar goes quiet on the click, and
  /// the server pass follows per space, because Discord has no route that
  /// marks an account read in one call.
  void markAllChannelsRead() {
    final workspace = _workspace;
    if (workspace == null) return;
    final activeIds = workspace.channels
        .where((channel) => channel.unread || channel.mentionCount > 0)
        .map((channel) => channel.id)
        .toSet();
    if (activeIds.isEmpty) return;
    _workspace = workspace.copyWith(
      channels: [
        for (final channel in workspace.channels)
          activeIds.contains(channel.id)
              ? channel.markRead().clearUnreadBoundary()
              : channel,
      ],
    );
    for (final channelId in activeIds) {
      _persistChannelActivity(channelId);
    }
    for (final spaceId in workspace.spaces.map((space) => space.id)) {
      unawaited(markSpaceRead(spaceId));
    }
    _notify();
  }

  /// Marks every channel of [spaceId] the account can see as read.
  Future<void> markSpaceRead(String spaceId) async {
    final repository = _repository.readState;
    final workspace = _workspace;
    if (repository == null || workspace == null) return;
    final permissions = WorkspacePermissions(workspace);
    await repository
        .markSpaceRead(
          spaceId,
          workspace
              .channelsFor(spaceId)
              .where(
                (channel) =>
                    permissions.can(DiscordPermissions.viewChannel, channel),
              ),
        )
        .catchError(_absorbReadStateFailure);
  }

  /// Mutes or unmutes [channel], optionally only for [windowSeconds].
  Future<void> setChannelMuted(
    ConversationChannel channel, {
    required bool muted,
    int? windowSeconds,
  }) => _editOverride(
    channel,
    ChannelNotificationOverridePatch(
      muted: muted,
      muteConfig: muted && windowSeconds != null
          ? NotificationMuteConfig.forWindow(windowSeconds, now: DateTime.now())
          : null,
      // Unmuting clears the expiry with it, or a later mute would inherit an
      // end time that has already passed and lapse immediately.
      clearMuteConfig: !muted || windowSeconds == null,
    ),
  );

  Future<void> setChannelNotificationLevel(
    ConversationChannel channel,
    MessageNotificationLevel level,
  ) => _editOverride(
    channel,
    ChannelNotificationOverridePatch(messageNotifications: level),
  );

  Future<void> setSpaceMuted(
    String spaceId, {
    required bool muted,
    int? windowSeconds,
  }) => _editSpaceSettings(
    spaceId,
    GuildNotificationSettingsPatch(
      muted: muted,
      muteConfig: muted && windowSeconds != null
          ? NotificationMuteConfig.forWindow(windowSeconds, now: DateTime.now())
          : null,
      clearMuteConfig: !muted || windowSeconds == null,
    ),
  );

  Future<void> setSpaceNotificationLevel(
    String spaceId,
    MessageNotificationLevel level,
  ) => _editSpaceSettings(
    spaceId,
    GuildNotificationSettingsPatch(messageNotifications: level),
  );

  Future<void> setSpaceSuppressEveryone(String spaceId, bool value) =>
      _editSpaceSettings(
        spaceId,
        GuildNotificationSettingsPatch(suppressEveryone: value),
      );

  Future<void> setSpaceSuppressRoles(String spaceId, bool value) =>
      _editSpaceSettings(
        spaceId,
        GuildNotificationSettingsPatch(suppressRoles: value),
      );

  Future<void> setSpaceMobilePush(String spaceId, bool value) =>
      _editSpaceSettings(
        spaceId,
        GuildNotificationSettingsPatch(mobilePush: value),
      );

  Future<void> _editOverride(
    ConversationChannel channel,
    ChannelNotificationOverridePatch patch,
  ) async {
    final repository = _repository.readState;
    if (repository == null) return;
    await repository
        .updateChannelNotificationOverride(
          spaceId: channel.spaceId,
          channelId: channel.id,
          patch: patch,
        )
        .catchError(_absorbReadStateFailure);
    _notify();
  }

  Future<void> _editSpaceSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  ) async {
    final repository = _repository.readState;
    if (repository == null) return;
    await repository
        .updateSpaceNotificationSettings(spaceId, patch)
        .catchError(_absorbReadStateFailure);
    _notify();
  }

  /// A failed acknowledgement is not a failed session.
  ///
  /// The optimistic value already went into the store, and the next `READY`
  /// re-reads the truth from the server, so surfacing this as the controller's
  /// error would replace a working chat window with a failure screen over an
  /// unread pip.
  void _absorbReadStateFailure(Object error) => developer.log(
    'Read-state update failed: $error',
    name: 'flucord.readstate',
    level: 900,
  );
}
