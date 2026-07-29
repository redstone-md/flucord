import 'discord_snowflake.dart';
import 'message_component.dart';
import 'guild_membership.dart';
import 'message_embed.dart';
import 'permission_overwrite.dart';

part 'community_space.dart';
part 'message_models.dart';
part 'message_poll.dart';
part 'message_sticker.dart';
part 'channel_category.dart';
part 'conversation_channel.dart';
part 'forum_models.dart';
part 'guild_emoji.dart';
part 'guild_sticker.dart';
part 'guild_scheduled_event.dart';
part 'guild_scheduled_event_editing.dart';
part 'user_activity.dart';
part 'user_presence.dart';
part 'workspace_member.dart';

enum ChannelKind { text, voice, forum, media }

final class PendingAttachment {
  static const maxCount = 10;

  const PendingAttachment({
    required this.name,
    required this.path,
    required this.size,
  });

  final String name;
  final String path;
  final int size;
}

final class ChatWorkspace {
  ChatWorkspace({
    required List<CommunitySpace> spaces,
    required List<ConversationChannel> channels,
    required List<Member> members,
    required List<ChatMessage> messages,
    required this.currentMemberId,
    List<CommunityRole> roles = const [],
    List<ChannelCategory> categories = const [],
    List<GuildEmoji> emojis = const [],
    List<GuildSticker> stickers = const [],
  }) : spaces = List.unmodifiable(spaces),
       channels = List.unmodifiable(channels),
       members = List.unmodifiable(members),
       messages = List.unmodifiable(messages),
       roles = List.unmodifiable(roles),
       categories = List.unmodifiable(categories),
       emojis = List.unmodifiable(emojis),
       stickers = List.unmodifiable(stickers);

  final List<CommunitySpace> spaces;
  final List<ConversationChannel> channels;
  final List<Member> members;
  final List<ChatMessage> messages;
  final List<CommunityRole> roles;
  final List<ChannelCategory> categories;
  final List<GuildEmoji> emojis;
  final List<GuildSticker> stickers;
  final String currentMemberId;

  List<ConversationChannel> channelsFor(String spaceId) => channels
      .where((channel) => channel.spaceId == spaceId)
      .toList(growable: false);

  List<ChatMessage> messagesFor(String channelId) => messages
      .where((message) => message.channelId == channelId)
      .toList(growable: false);

  List<ChannelCategory> categoriesFor(String spaceId) => categories
      .where((category) => category.spaceId == spaceId)
      .toList(growable: false);

  CommunitySpace spaceById(String id) =>
      spaces.firstWhere((space) => space.id == id);

  ConversationChannel channelById(String id) =>
      channels.firstWhere((channel) => channel.id == id);

  Member memberById(String id) =>
      members.firstWhere((member) => member.id == id);

  Member? memberOrNull(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  ConversationChannel? channelOrNull(String id) {
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }

  CommunityRole? roleOrNull(String id) {
    for (final role in roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  ChatWorkspace copyWith({
    List<CommunitySpace>? spaces,
    List<ConversationChannel>? channels,
    List<Member>? members,
    List<ChatMessage>? messages,
    List<CommunityRole>? roles,
    List<ChannelCategory>? categories,
    List<GuildEmoji>? emojis,
    List<GuildSticker>? stickers,
    String? currentMemberId,
  }) => ChatWorkspace(
    spaces: spaces ?? this.spaces,
    channels: channels ?? this.channels,
    members: members ?? this.members,
    messages: messages ?? this.messages,
    roles: roles ?? this.roles,
    categories: categories ?? this.categories,
    emojis: emojis ?? this.emojis,
    stickers: stickers ?? this.stickers,
    currentMemberId: currentMemberId ?? this.currentMemberId,
  );

  ChatWorkspace retainDirectMessagesFrom(ChatWorkspace? cached) {
    if (cached == null || cached.currentMemberId != currentMemberId) {
      return this;
    }
    final directSpaceIds = cached.spaces
        .where((space) => space.isDirectMessages)
        .map((space) => space.id)
        .toSet();
    final directChannels = cached.channels
        .where((channel) => directSpaceIds.contains(channel.spaceId))
        .toList();
    final directChannelIds = directChannels
        .map((channel) => channel.id)
        .toSet();
    final directMessages = cached.messages
        .where((message) => directChannelIds.contains(message.channelId))
        .toList();
    final directMemberIds = <String>{
      currentMemberId,
      for (final channel in directChannels) ?channel.recipientId,
      for (final message in directMessages) message.authorId,
    };
    final memberMap = {for (final member in members) member.id: member};
    for (final member in cached.members) {
      if (directMemberIds.contains(member.id)) {
        memberMap[member.id] = _mergeMember(
          member,
          memberMap[member.id] ?? member,
        );
      }
    }
    return copyWith(
      spaces:
          [
                ...spaces.where((space) => space.isDirectMessages),
                ...cached.spaces.where((space) => space.isDirectMessages),
                ...spaces.where((space) => !space.isDirectMessages),
              ]
              .fold(<String, CommunitySpace>{}, (map, space) {
                map[space.id] = space;
                return map;
              })
              .values
              .toList(),
      channels: [
        ...directChannels,
        ...channels.where((channel) => !directChannelIds.contains(channel.id)),
      ],
      members: memberMap.values.toList(),
      messages: [
        ...directMessages,
        ...messages.where(
          (message) => !directChannelIds.contains(message.channelId),
        ),
      ],
    );
  }

  ChatWorkspace restoreChannelActivityFrom(ChatWorkspace? cached) {
    if (cached == null || cached.currentMemberId != currentMemberId) {
      return this;
    }
    final cachedChannels = {
      for (final channel in cached.channels) channel.id: channel,
    };
    return copyWith(
      channels: [
        for (final channel in channels)
          channel.withActivityOf(cachedChannels[channel.id] ?? channel),
      ],
    );
  }

  ChatWorkspace mergeHistory(
    ChannelHistory history, {
    bool replaceChannel = true,
  }) {
    final memberMap = {for (final member in members) member.id: member};
    for (final member in history.members) {
      memberMap[member.id] = _mergeMember(memberMap[member.id], member);
    }
    final channelMessages = <String, ChatMessage>{
      if (!replaceChannel)
        for (final message in messages)
          if (message.channelId == history.channelId) message.id: message,
      for (final message in history.messages) message.id: message,
    };
    final nextMessages = [
      ...messages.where((message) => message.channelId != history.channelId),
      ...channelMessages.values,
    ];
    nextMessages.sort((left, right) => left.sentAt.compareTo(right.sentAt));
    return copyWith(members: memberMap.values.toList(), messages: nextMessages);
  }

  ChatWorkspace mergeInitialHistory(
    ChannelHistory history, {
    bool retainExisting = false,
  }) => mergeHistory(
    history,
    replaceChannel:
        !retainExisting &&
        channelById(history.channelId).firstUnreadMessageId == null,
  );

  ChatWorkspace upsertMessage(ChatMessage message, {Member? member}) {
    final nextMessages = [
      ...messages.where((existing) => existing.id != message.id),
      message,
    ]..sort((left, right) => left.sentAt.compareTo(right.sentAt));
    final nextMembers = member == null
        ? members
        : _mergeMemberInto(members, member);
    // Unread is decided by comparing this pointer against the read state's ack
    // cursor, so a message that arrives without advancing it would be invisible
    // to every unread surface until the next gateway channel update.
    return copyWith(
      messages: nextMessages,
      members: nextMembers,
    ).recordLatestMessage(message.channelId, message.id);
  }

  /// Records [messageId] as the newest message in [channelId].
  ChatWorkspace recordLatestMessage(String channelId, String messageId) =>
      updateChannel(
        channelId,
        (channel) => channel.withLatestMessage(messageId),
      );

  ChatWorkspace upsertMember(Member member) =>
      copyWith(members: _mergeMemberInto(members, member));

  /// Folds a batch of members in with one pass over the member table.
  ///
  /// A member-list page carries up to a hundred members at once; upserting
  /// them one at a time would rebuild the whole table per member and turn a
  /// single roster page into quadratic work.
  ChatWorkspace upsertMembers(Iterable<Member> incoming) {
    if (incoming.isEmpty) return this;
    final merged = <String, Member>{
      for (final member in members) member.id: member,
    };
    for (final member in incoming) {
      merged[member.id] = _mergeMember(merged[member.id], member);
    }
    return copyWith(members: merged.values.toList(growable: false));
  }

  ChatWorkspace upsertSpace(CommunitySpace space) => copyWith(
    spaces: [...spaces.where((existing) => existing.id != space.id), space],
  );

  ChatWorkspace upsertCategory(ChannelCategory category) => copyWith(
    categories: [
      ...categories.where((existing) => existing.id != category.id),
      category,
    ],
  );

  ChatWorkspace removeCategory(String categoryId) => copyWith(
    categories: categories
        .where((category) => category.id != categoryId)
        .toList(),
  );

  /// Applies a gateway presence to the member it names.
  ///
  /// A presence for somebody the member table has never heard of is dropped
  /// rather than turned into a nameless row: Discord streams presence for
  /// friends and for every subscribed guild, so an unmatched id is routine.
  ChatWorkspace applyPresence(String memberId, UserPresence presence) =>
      copyWith(
        members: [
          for (final member in members)
            member.id == memberId ? member.withPresence(presence) : member,
        ],
      );

  /// Applies a batch of presences with one pass over the member table.
  ///
  /// `READY_SUPPLEMENTAL` alone carries a presence for every online friend and
  /// every subscribed guild member, and folding them in one at a time would
  /// rebuild the table once per presence.
  ChatWorkspace applyPresences(Map<String, UserPresence> presences) {
    if (presences.isEmpty) return this;
    var touched = false;
    final next = <Member>[];
    for (final member in members) {
      final presence = presences[member.id];
      if (presence == null) {
        next.add(member);
        continue;
      }
      touched = true;
      next.add(member.withPresence(presence));
    }
    return touched ? copyWith(members: next) : this;
  }

  ChatWorkspace removeMemberFromSpace(String memberId, String spaceId) {
    final next = <Member>[];
    for (final member in members) {
      if (member.id != memberId) {
        next.add(member);
        continue;
      }
      final spaces = {...member.spaceIds}..remove(spaceId);
      final roles = {...member.rolesBySpace}..remove(spaceId);
      final avatars = {...member.avatarUrlsBySpace}..remove(spaceId);
      if (spaces.isNotEmpty || member.spaceIds.isEmpty) {
        next.add(
          member.copyWith(
            spaceIds: spaces,
            rolesBySpace: roles,
            avatarUrlsBySpace: avatars,
          ),
        );
      }
    }
    return copyWith(members: next);
  }

  ChatWorkspace markChannelRead(String channelId) =>
      updateChannel(channelId, (channel) => channel.markRead());

  ChatWorkspace clearChannelUnreadBoundary(String channelId) =>
      updateChannel(channelId, (channel) => channel.clearUnreadBoundary());

  ChatWorkspace markChannelUnread(
    String channelId, {
    required String messageId,
    required bool mention,
  }) => updateChannel(
    channelId,
    (channel) => channel.markUnread(messageId: messageId, mention: mention),
  );

  ChatWorkspace updateChannel(
    String channelId,
    ConversationChannel Function(ConversationChannel channel) update,
  ) => copyWith(
    channels: [
      for (final channel in channels)
        channel.id == channelId ? update(channel) : channel,
    ],
  );

  ChatWorkspace removeMessage(String messageId) => copyWith(
    messages: messages.where((message) => message.id != messageId).toList(),
    channels: [
      for (final channel in channels)
        channel.firstUnreadMessageId == messageId
            ? channel.clearUnreadBoundary()
            : channel,
    ],
  );

  ChatWorkspace upsertChannel(ConversationChannel channel) {
    final previous = channelOrNull(channel.id);
    final next = previous == null ? channel : channel.withActivityOf(previous);
    return copyWith(
      channels: [
        ...channels.where((existing) => existing.id != channel.id),
        next,
      ],
    );
  }

  ChatWorkspace removeChannel(String channelId) {
    final nextChannels = channels
        .where((channel) => channel.id != channelId)
        .toList();
    return copyWith(
      channels: nextChannels,
      messages: messages
          .where((message) => message.channelId != channelId)
          .toList(),
    );
  }

  static List<Member> _mergeMemberInto(List<Member> current, Member incoming) {
    final existing = current.where((member) => member.id == incoming.id);
    if (existing.isEmpty) return [...current, incoming];
    final merged = _mergeMember(existing.first, incoming);
    return [...current.where((member) => member.id != incoming.id), merged];
  }

  static Member _mergeMember(Member? previous, Member incoming) {
    if (previous == null) return incoming;
    return incoming.copyWith(
      spaceIds: {...previous.spaceIds, ...incoming.spaceIds},
      rolesBySpace: {...previous.rolesBySpace, ...incoming.rolesBySpace},
      avatarUrl: incoming.avatarUrl ?? previous.avatarUrl,
      avatarUrlsBySpace: {
        ...previous.avatarUrlsBySpace,
        ...incoming.avatarUrlsBySpace,
      },
      membershipsBySpace: {
        ...previous.membershipsBySpace,
        ...incoming.membershipsBySpace,
      },
      presence: incoming.presence == Presence.offline
          ? previous.presence
          : incoming.presence,
      // A member payload carries no presence, so the mapper defaults it to
      // offline; letting that erase a presence the gateway already reported
      // would blank out every activity the moment the member is re-mapped.
      presenceDetail: incoming.presenceDetail ?? previous.presenceDetail,
    );
  }
}

final class ChannelHistory {
  ChannelHistory({
    required this.channelId,
    required List<ChatMessage> messages,
    required List<Member> members,
  }) : messages = List.unmodifiable(messages),
       members = List.unmodifiable(members);

  final String channelId;
  final List<ChatMessage> messages;
  final List<Member> members;
}

final class ChannelHistoryPage {
  const ChannelHistoryPage({required this.history, required this.hasMore});

  final ChannelHistory history;
  final bool hasMore;
}
