part of 'read_state.dart';

/// Everything the account's read state and notification settings say, as one
/// immutable value.
///
/// This is server state, not a local cache: it arrives whole in `READY`, is
/// revised by five gateway dispatches, and disagreeing with it is always the
/// client's mistake. Surfaces therefore ask it questions rather than keeping
/// unread flags of their own.
final class ReadStateSnapshot {
  ReadStateSnapshot({
    Map<String, ReadState> readStates = const {},
    Map<String, GuildNotificationSettings> settings = const {},
    this.accountNotificationFlags = 0,
    this.readStateVersion = 0,
    this.userGuildSettingsVersion = 0,
  }) : readStates = Map.unmodifiable(readStates),
       settings = Map.unmodifiable(settings);

  static final empty = ReadStateSnapshot();

  /// Read states by [ReadState.key]: bare channel id for channel read states,
  /// `type:entity` for every other type.
  final Map<String, ReadState> readStates;

  /// Notification settings by space id, with direct messages filed under
  /// [CommunitySpace.directMessagesId] exactly as Discord addresses them.
  final Map<String, GuildNotificationSettings> settings;

  /// `READY.notification_settings.flags`.
  final int accountNotificationFlags;
  final int readStateVersion;
  final int userGuildSettingsVersion;

  /// R04: with `USE_NEW_NOTIFICATIONS` off, every unread-badge question
  /// short-circuits to "all messages" whatever the flag bits say.
  bool get usesNewNotifications =>
      accountNotificationFlags & AccountNotificationFlags.useNewNotifications !=
      0;

  ReadState? forChannel(String channelId) => readStates[channelId];

  ReadState? forEntity(ReadStateType type, String entityId) =>
      readStates[ReadState.keyFor(type, entityId)];

  GuildNotificationSettings settingsFor(String spaceId) =>
      settings[spaceId] ?? GuildNotificationSettings.defaults(spaceId);

  /// The highest acknowledged id across every read state, `"0"` when there is
  /// none. R03/R09: this is IDENTIFY's `highest_last_message_id`, compared as a
  /// string snowflake rather than as a number.
  String get highestLastMessageId => _highestAckedIn(readStates.values);

  /// The same maximum, taken over the read states of [privateChannelIds] only:
  /// IDENTIFY's `private_channels_version` (R09).
  String privateChannelsVersion(Set<String> privateChannelIds) =>
      _highestAckedIn(
        readStates.values.where(
          (state) =>
              state.type == ReadStateType.channel &&
              privateChannelIds.contains(state.entityId),
        ),
      );

  /// Whether [channel] is silenced, by its own override or by its space.
  bool isChannelMuted(ConversationChannel channel, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final space = settingsFor(channel.spaceId);
    if (space.isMutedAt(at)) return true;
    if (space.overrideFor(channel.id)?.isMutedAt(at) ?? false) return true;
    // A thread inherits its parent's mute, and so does a channel inside a muted
    // category: Discord silences the container, not each row under it.
    return space.overrideFor(channel.parentId)?.isMutedAt(at) ?? false;
  }

  bool isSpaceMuted(String spaceId, {DateTime? now}) =>
      settingsFor(spaceId).isMutedAt(now ?? DateTime.now());

  /// The notification level in force for [channel].
  ///
  /// R04's resolution order: channel override, then the parent category or
  /// forum, then the guild default, treating `3 NULL` as "ask the next level".
  MessageNotificationLevel notificationLevelFor(ConversationChannel channel) {
    final space = settingsFor(channel.spaceId);
    for (final candidate in [
      space.overrideFor(channel.id)?.messageNotifications,
      space.overrideFor(channel.parentId)?.messageNotifications,
      space.messageNotifications,
    ]) {
      if (candidate != null && candidate != MessageNotificationLevel.inherit) {
        return candidate;
      }
    }
    return MessageNotificationLevel.allMessages;
  }

  /// Whether [channel] should light up for every message or only for mentions.
  ///
  /// R04 resolves this from its own chain of flag bits — channel override,
  /// parent override, guild — and only falls back to the notification level
  /// when none of them is set.
  UnreadBadge unreadBadgeFor(ConversationChannel channel) {
    if (!usesNewNotifications) return UnreadBadge.allMessages;
    final space = settingsFor(channel.spaceId);
    final resolved =
        space.overrideFor(channel.id)?.unreadBadge ??
        space.overrideFor(channel.parentId)?.unreadBadge ??
        space.unreadBadge;
    if (resolved != null) return resolved;
    return notificationLevelFor(channel) == MessageNotificationLevel.allMessages
        ? UnreadBadge.allMessages
        : UnreadBadge.onlyMentions;
  }

  /// Whether a desktop notification is allowed for a message in [channel].
  ///
  /// [mentionsEveryone] is passed separately from [mentionsCurrentMember]
  /// because `suppress_everyone` removes exactly that one reason to notify: an
  /// `@everyone` that also names the account by id still counts as a mention.
  bool allowsDesktopNotification(
    ConversationChannel channel, {
    required bool mentionsCurrentMember,
    bool mentionsEveryone = false,
    DateTime? now,
  }) {
    if (isChannelMuted(channel, now: now)) return false;
    final space = settingsFor(channel.spaceId);
    final mentioned =
        mentionsCurrentMember || (mentionsEveryone && !space.suppressEveryone);
    // Written as tests rather than as a switch because
    // `notificationLevelFor` never answers "ask the next level", and an arm
    // for that case would be a branch no test could ever reach.
    final level = notificationLevelFor(channel);
    if (level == MessageNotificationLevel.noMessages) return false;
    if (level == MessageNotificationLevel.onlyMentions) return mentioned;
    return true;
  }

  ReadStateSnapshot copyWith({
    Map<String, ReadState>? readStates,
    Map<String, GuildNotificationSettings>? settings,
    int? accountNotificationFlags,
    int? readStateVersion,
    int? userGuildSettingsVersion,
  }) => ReadStateSnapshot(
    readStates: readStates ?? this.readStates,
    settings: settings ?? this.settings,
    accountNotificationFlags:
        accountNotificationFlags ?? this.accountNotificationFlags,
    readStateVersion: readStateVersion ?? this.readStateVersion,
    userGuildSettingsVersion:
        userGuildSettingsVersion ?? this.userGuildSettingsVersion,
  );

  static String _highestAckedIn(Iterable<ReadState> states) {
    var highest = '0';
    for (final state in states) {
      final acked = state.lastAckedId;
      if (acked == null) continue;
      if (DiscordSnowflake.compare(acked, highest) > 0) highest = acked;
    }
    return highest;
  }
}

/// Folds server read state into a workspace snapshot.
///
/// The rail pips, the NEW divider and the Inbox all read
/// [ConversationChannel.unread], [ConversationChannel.mentionCount] and
/// [ConversationChannel.firstUnreadMessageId], so making the server
/// authoritative is a matter of recomputing those three from the read state
/// rather than of teaching each surface a second source of truth.
extension ReadStateProjection on ChatWorkspace {
  ChatWorkspace applyReadState(ReadStateSnapshot snapshot) {
    if (snapshot.readStates.isEmpty) return this;
    final firstUnread = <String, String>{};
    for (final message in messages) {
      final state = snapshot.forChannel(message.channelId);
      if (state == null || firstUnread.containsKey(message.channelId)) continue;
      if (state.isBehind(message.id)) {
        firstUnread[message.channelId] = message.id;
      }
    }
    return copyWith(
      channels: [
        for (final channel in channels)
          _projectedChannel(channel, snapshot, firstUnread[channel.id]),
      ],
    );
  }
}

/// A channel the server holds no read state for keeps whatever it already had.
/// Silence is not disagreement: Discord garbage-collects read states it
/// considers stale, and reading that as "everything is read" would wipe an
/// unread marker the account can still see in the official client.
ConversationChannel _projectedChannel(
  ConversationChannel channel,
  ReadStateSnapshot snapshot,
  String? firstUnreadMessageId,
) {
  final state = snapshot.forChannel(channel.id);
  if (state == null) return channel;
  final unread = state.isBehind(channel.lastMessageId);
  return channel.copyWith(
    unread: unread,
    mentionCount: state.mentionCount,
    firstUnreadMessageId: unread ? firstUnreadMessageId : null,
  );
}
