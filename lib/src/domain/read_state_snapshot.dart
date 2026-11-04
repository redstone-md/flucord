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

  /// Whether [other] holds the same notification settings. A surface reads only
  /// these from a snapshot: cursors reach it through the channels they fold into.
  bool sameSettingsAs(ReadStateSnapshot other) =>
      accountNotificationFlags == other.accountNotificationFlags &&
      settings.length == other.settings.length &&
      settings.entries.every(
        (entry) => identical(other.settings[entry.key], entry.value),
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

  /// Whether [channel] should read as unread in a list. A mention always
  /// shows. Otherwise the resolved unread badge decides: a channel set to "only
  /// mentions" stays quiet even though the server considers it unread.
  bool showsUnread(ConversationChannel channel) {
    if (channel.mentionCount > 0) return true;
    if (!channel.unread) return false;
    return unreadBadgeFor(channel) == UnreadBadge.allMessages;
  }

  /// Whether [message], from somebody else, counts as a mention in [channel].
  bool countsAsMention(ConversationChannel channel, ChatMessage message) =>
      settingsFor(channel.spaceId).countsAsMention(
        namesAccount: message.mentionsCurrentMember,
        mentionsEveryone: message.mentionsEveryone,
        directMessage: channel.isDirectMessage,
      );

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
    final mentioned = settingsFor(channel.spaceId).countsAsMention(
      namesAccount: mentionsCurrentMember,
      mentionsEveryone: mentionsEveryone,
      directMessage: channel.isDirectMessage,
    );
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
  /// Answers with this same workspace when no channel changed, and a channel
  /// that did not change keeps its instance, so caches keyed on them still hit.
  ChatWorkspace applyReadState(ReadStateSnapshot snapshot) {
    if (snapshot.readStates.isEmpty) return this;
    var changed = false;
    final projected = <ConversationChannel>[];
    for (final channel in channels) {
      final next = _projectedChannel(channel, snapshot);
      changed = changed || !identical(next, channel);
      projected.add(next);
    }
    return changed ? copyWith(channels: projected) : this;
  }

  /// The id of the first held message of [state]'s channel newer than its
  /// cursor. Null with no such message.
  String? _firstUnreadIn(ReadState state) => messagesFor(
    state.entityId,
  ).where((message) => state.isBehind(message.id)).firstOrNull?.id;

  /// Sets a channel's boundary to its first held message newer than [state]'s
  /// cursor. [state] is what the channel's read state was before it was read,
  /// so this is how a channel that an open acked still gets its NEW line.
  ///
  /// With no such message held, or with the boundary already there, the
  /// workspace stays as it is.
  ChatWorkspace withUnreadBoundaryFrom(ReadState state) {
    final first = _firstUnreadIn(state);
    if (first == null ||
        channelOrNull(state.entityId)?.firstUnreadMessageId == first) {
      return this;
    }
    return updateChannel(
      state.entityId,
      (channel) => channel.copyWith(firstUnreadMessageId: first),
    );
  }

  /// Clears the boundary of every read channel except [activeChannelId], whose
  /// NEW line is on screen. A channel read somewhere else, while the client was
  /// not looking at it, has nothing new to show when it opens.
  ChatWorkspace clearReadBoundaries({String? activeChannelId}) {
    bool isStale(ConversationChannel channel) =>
        !channel.unread &&
        channel.firstUnreadMessageId != null &&
        channel.id != activeChannelId;
    if (!channels.any(isStale)) return this;
    return copyWith(
      channels: [
        for (final channel in channels)
          isStale(channel) ? channel.clearUnreadBoundary() : channel,
      ],
    );
  }

  /// A channel the server holds no read state for keeps whatever it already had.
  /// Silence is not disagreement: Discord garbage-collects read states it
  /// considers stale, and reading that as "everything is read" would wipe an
  /// unread marker the account can still see in the official client.
  ///
  /// A channel that is read keeps its boundary: the NEW line outlives the ack
  /// that opening the channel sends. Clearing it is left to the explicit clear.
  /// An unread channel keeps its boundary too when no held message can replace
  /// it.
  ConversationChannel _projectedChannel(
    ConversationChannel channel,
    ReadStateSnapshot snapshot,
  ) {
    final state = snapshot.forChannel(channel.id);
    if (state == null) return channel;
    final unread = state.isBehind(channel.lastMessageId);
    final boundary =
        (unread ? _firstUnreadIn(state) : null) ?? channel.firstUnreadMessageId;
    if (unread == channel.unread &&
        state.mentionCount == channel.mentionCount &&
        boundary == channel.firstUnreadMessageId) {
      return channel;
    }
    return channel.copyWith(
      unread: unread,
      mentionCount: state.mentionCount,
      firstUnreadMessageId: boundary,
    );
  }
}
