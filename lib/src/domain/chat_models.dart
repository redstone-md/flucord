import 'message_embed.dart';

part 'message_models.dart';

enum ChannelKind { text, voice }

enum Presence { online, idle, offline }

enum SpaceKind { guild, directMessages }

final class CommunitySpace {
  static const directMessagesId = '@me';

  const CommunitySpace({
    required this.id,
    required this.name,
    required this.monogram,
    required this.colorValue,
    this.iconUrl,
    this.kind = SpaceKind.guild,
  });

  const CommunitySpace.directMessages()
    : id = directMessagesId,
      name = 'Direct Messages',
      monogram = 'DM',
      colorValue = 0xff456b5a,
      iconUrl = null,
      kind = SpaceKind.directMessages;

  final String id;
  final String name;
  final String monogram;
  final int colorValue;
  final String? iconUrl;
  final SpaceKind kind;

  bool get isDirectMessages => kind == SpaceKind.directMessages;
}

final class CommunityRole {
  const CommunityRole({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.position,
    this.colorValue,
  });

  final String id;
  final String spaceId;
  final String name;
  final int position;
  final int? colorValue;
}

final class ConversationChannel {
  const ConversationChannel({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.topic,
    required this.kind,
    this.parentId,
    this.isThread = false,
    this.recipientId,
    this.unread = false,
    this.mentionCount = 0,
  });

  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelKind kind;
  final String? parentId;
  final bool isThread;
  final String? recipientId;
  final bool unread;
  final int mentionCount;

  bool get isDirectMessage => recipientId != null;

  ConversationChannel copyWith({bool? unread, int? mentionCount}) =>
      ConversationChannel(
        id: id,
        spaceId: spaceId,
        name: name,
        topic: topic,
        kind: kind,
        parentId: parentId,
        isThread: isThread,
        recipientId: recipientId,
        unread: unread ?? this.unread,
        mentionCount: mentionCount ?? this.mentionCount,
      );
}

final class DirectConversation {
  const DirectConversation({required this.channel, required this.recipient});

  final ConversationChannel channel;
  final Member recipient;
}

final class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.role,
    required this.presence,
    required this.colorValue,
    this.spaceIds = const {},
    this.rolesBySpace = const {},
    this.avatarUrl,
    this.avatarUrlsBySpace = const {},
  });

  final String id;
  final String displayName;
  final String initials;
  final String role;
  final Presence presence;
  final int colorValue;
  final Set<String> spaceIds;
  final Map<String, String> rolesBySpace;
  final String? avatarUrl;
  final Map<String, String> avatarUrlsBySpace;

  String roleFor(String spaceId) => rolesBySpace[spaceId] ?? role;
  String? avatarUrlFor(String? spaceId) =>
      spaceId == null ? avatarUrl : avatarUrlsBySpace[spaceId] ?? avatarUrl;

  Member copyWith({
    String? displayName,
    String? role,
    Presence? presence,
    int? colorValue,
    Set<String>? spaceIds,
    Map<String, String>? rolesBySpace,
    String? avatarUrl,
    Map<String, String>? avatarUrlsBySpace,
  }) => Member(
    id: id,
    displayName: displayName ?? this.displayName,
    initials: initials,
    role: role ?? this.role,
    presence: presence ?? this.presence,
    colorValue: colorValue ?? this.colorValue,
    spaceIds: spaceIds ?? this.spaceIds,
    rolesBySpace: rolesBySpace ?? this.rolesBySpace,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    avatarUrlsBySpace: avatarUrlsBySpace ?? this.avatarUrlsBySpace,
  );
}

final class PendingAttachment {
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
  }) : spaces = List.unmodifiable(spaces),
       channels = List.unmodifiable(channels),
       members = List.unmodifiable(members),
       messages = List.unmodifiable(messages),
       roles = List.unmodifiable(roles);

  final List<CommunitySpace> spaces;
  final List<ConversationChannel> channels;
  final List<Member> members;
  final List<ChatMessage> messages;
  final List<CommunityRole> roles;
  final String currentMemberId;

  List<ConversationChannel> channelsFor(String spaceId) => channels
      .where((channel) => channel.spaceId == spaceId)
      .toList(growable: false);

  List<ChatMessage> messagesFor(String channelId) => messages
      .where((message) => message.channelId == channelId)
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
    String? currentMemberId,
  }) => ChatWorkspace(
    spaces: spaces ?? this.spaces,
    channels: channels ?? this.channels,
    members: members ?? this.members,
    messages: messages ?? this.messages,
    roles: roles ?? this.roles,
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

  ChatWorkspace upsertMessage(ChatMessage message, {Member? member}) {
    final nextMessages = [
      ...messages.where((existing) => existing.id != message.id),
      message,
    ]..sort((left, right) => left.sentAt.compareTo(right.sentAt));
    final nextMembers = member == null
        ? members
        : _mergeMemberInto(members, member);
    return copyWith(messages: nextMessages, members: nextMembers);
  }

  ChatWorkspace upsertMember(Member member) =>
      copyWith(members: _mergeMemberInto(members, member));

  ChatWorkspace upsertSpace(CommunitySpace space) => copyWith(
    spaces: [...spaces.where((existing) => existing.id != space.id), space],
  );

  ChatWorkspace updatePresence(String memberId, Presence presence) => copyWith(
    members: [
      for (final member in members)
        member.id == memberId ? member.copyWith(presence: presence) : member,
    ],
  );

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

  ChatWorkspace markChannelRead(String channelId) => updateChannel(
    channelId,
    (channel) => channel.copyWith(unread: false, mentionCount: 0),
  );

  ChatWorkspace markChannelUnread(String channelId, {required bool mention}) =>
      updateChannel(
        channelId,
        (channel) => channel.copyWith(
          unread: true,
          mentionCount: mention
              ? channel.mentionCount + 1
              : channel.mentionCount,
        ),
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
  );

  ChatWorkspace upsertChannel(ConversationChannel channel) => copyWith(
    channels: [
      ...channels.where((existing) => existing.id != channel.id),
      channel,
    ],
  );

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
      presence: incoming.presence == Presence.offline
          ? previous.presence
          : incoming.presence,
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
