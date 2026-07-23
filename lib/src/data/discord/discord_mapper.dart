import '../../domain/chat_models.dart';
import '../message_embed_codec.dart';
import 'discord_cdn.dart';
import 'discord_mention_matcher.dart';

final class DiscordMappedDirectMessage {
  const DiscordMappedDirectMessage({
    required this.channel,
    required this.recipient,
  });

  final ConversationChannel channel;
  final Member recipient;
}

final class DiscordMapper {
  static const directMessagesSpaceId = CommunitySpace.directMessagesId;
  static const _colors = [
    0xff456b5a,
    0xff765341,
    0xff5f5b76,
    0xff59636a,
    0xff486b70,
    0xff6f5967,
  ];

  ChatWorkspace workspace({
    required Map<String, Object?> currentUser,
    required List<Map<String, Object?>> guilds,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
    Map<String, List<Map<String, Object?>>> threadsByGuild = const {},
    Map<String, List<Map<String, Object?>>> membersByGuild = const {},
    Map<String, List<Map<String, Object?>>> rolesByGuild = const {},
    List<Map<String, Object?>> directChannels = const [],
    bool includeDirectMessagesSpace = false,
  }) {
    final spaces = <CommunitySpace>[];
    final channels = <ConversationChannel>[];
    final categories = <ChannelCategory>[];
    final roles = <CommunityRole>[];
    final members = <String, Member>{};
    if (includeDirectMessagesSpace || directChannels.isNotEmpty) {
      spaces.add(directMessagesSpace);
    }
    for (final payload in directChannels) {
      final mapped = directMessage(payload, currentUser['id']! as String);
      if (mapped == null) continue;
      channels.add(mapped.channel);
      members[mapped.recipient.id] = mapped.recipient;
    }
    for (final guild in guilds) {
      final guildId = guild['id']! as String;
      final rawChannels = [
        ...(channelsByGuild[guildId] ?? const []),
        ...(threadsByGuild[guildId] ?? const []),
      ];
      final mappedChannels = rawChannels
          .map((channel) => this.channel(channel, guildId))
          .whereType<ConversationChannel>()
          .toList();
      if (mappedChannels.isEmpty) continue;
      spaces.add(_space(guild));
      channels.addAll(mappedChannels);
      categories.addAll(
        rawChannels
            .map((channel) => category(channel, guildId))
            .whereType<ChannelCategory>(),
      );
      roles.addAll(
        (rolesByGuild[guildId] ?? const []).map(
          (payload) => role(payload, guildId),
        ),
      );
      for (final payload in membersByGuild[guildId] ?? const []) {
        final mapped = guildMember(
          payload,
          guildId,
          rolesByGuild[guildId] ?? const [],
        );
        members[mapped.id] = _mergeMembers(members[mapped.id], mapped);
      }
    }
    final currentMember = member(
      currentUser,
      role: 'Discord bot',
      presence: Presence.online,
      spaceIds: spaces.map((space) => space.id).toSet(),
    );
    members[currentMember.id] = _mergeMembers(
      members[currentMember.id],
      currentMember,
    );
    return ChatWorkspace(
      spaces: spaces,
      channels: channels,
      roles: roles,
      categories: categories,
      members: members.values.toList(),
      messages: const [],
      currentMemberId: currentMember.id,
    );
  }

  CommunitySpace get directMessagesSpace =>
      const CommunitySpace.directMessages();

  DiscordMappedDirectMessage? directMessage(
    Map<String, Object?> payload,
    String currentUserId,
  ) {
    if (payload['type'] != 1) return null;
    final recipients = (payload['recipients'] as List? ?? const [])
        .whereType<Map>()
        .map((recipient) => recipient.cast<String, Object?>())
        .where((recipient) => recipient['id'] != currentUserId)
        .toList(growable: false);
    if (recipients.isEmpty) return null;
    final recipient = member(
      recipients.first,
      role: 'Direct message',
      spaceIds: const {directMessagesSpaceId},
    );
    return DiscordMappedDirectMessage(
      recipient: recipient,
      channel: ConversationChannel(
        id: payload['id']! as String,
        spaceId: directMessagesSpaceId,
        name: recipient.displayName,
        topic: 'Direct message with ${recipient.displayName}',
        kind: ChannelKind.text,
        recipientId: recipient.id,
      ),
    );
  }

  ChannelHistory history(
    String channelId,
    List<Map<String, Object?>> payloads, {
    String? currentMemberId,
  }) {
    final members = <String, Member>{};
    final messages = <ChatMessage>[];
    for (final payload in payloads.reversed) {
      final authorPayload = (payload['author']! as Map).cast<String, Object?>();
      final author = member(authorPayload);
      members[author.id] = author;
      messages.add(message(payload, currentMemberId: currentMemberId));
    }
    return ChannelHistory(
      channelId: channelId,
      messages: messages,
      members: members.values.toList(),
    );
  }

  ChatMessage message(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
    String? currentMemberId,
  }) {
    final rawContent = payload.containsKey('content')
        ? payload['content'] as String? ?? ''
        : fallback?.body ?? '';
    final attachments = payload.containsKey('attachments')
        ? (payload['attachments'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => _attachment(item.cast<String, Object?>()))
              .toList()
        : fallback?.attachments ?? const <MessageAttachment>[];
    final reactions = payload.containsKey('reactions')
        ? (payload['reactions'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => _reaction(item.cast<String, Object?>()))
              .toList()
        : fallback?.reactions ?? const <MessageReaction>[];
    final embeds = payload.containsKey('embeds')
        ? MessageEmbedCodec.listFrom(payload['embeds'])
        : fallback?.embeds ?? const [];
    final referenced = payload['referenced_message'];
    final reply = referenced is Map
        ? _reply(referenced.cast<String, Object?>())
        : fallback?.reply;
    return ChatMessage(
      id: payload['id'] as String? ?? fallback!.id,
      channelId: payload['channel_id'] as String? ?? fallback!.channelId,
      authorId: payload['author'] is Map
          ? (payload['author']! as Map)['id']! as String
          : fallback!.authorId,
      body: rawContent,
      sentAt: payload['timestamp'] is String
          ? DateTime.parse(payload['timestamp']! as String).toLocal()
          : fallback!.sentAt,
      isEdited: payload.containsKey('edited_timestamp')
          ? payload['edited_timestamp'] != null
          : fallback?.isEdited ?? false,
      isPinned: payload.containsKey('pinned')
          ? payload['pinned'] == true
          : fallback?.isPinned ?? false,
      mentionsCurrentMember: payload.containsKey('mentions')
          ? DiscordMentionMatcher.containsUser(payload, currentMemberId)
          : fallback?.mentionsCurrentMember ?? false,
      attachments: attachments,
      embeds: embeds,
      reactions: reactions,
      reply: reply,
    );
  }

  MessageAttachment _attachment(Map<String, Object?> payload) =>
      MessageAttachment(
        id: payload['id'] as String? ?? '',
        fileName: payload['filename'] as String? ?? 'attachment',
        url: payload['url'] as String? ?? '',
        size: payload['size'] as int? ?? 0,
        contentType: payload['content_type'] as String?,
        width: payload['width'] as int?,
        height: payload['height'] as int?,
      );

  MessageReaction _reaction(Map<String, Object?> payload) {
    final emoji =
        (payload['emoji'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return MessageReaction(
      emojiName: emoji['name'] as String? ?? '?',
      emojiId: emoji['id'] as String?,
      animated: emoji['animated'] as bool? ?? false,
      count: payload['count'] as int? ?? 0,
      reactedByCurrentUser: payload['me'] as bool? ?? false,
    );
  }

  MessageReply? _reply(Map<String, Object?> payload) {
    final id = payload['id'] as String?;
    final author = payload['author'];
    final authorId = author is Map ? author['id'] as String? : null;
    if (id == null || authorId == null) return null;
    return MessageReply(
      messageId: id,
      authorId: authorId,
      body: payload['content'] as String? ?? '',
    );
  }

  Member member(
    Map<String, Object?> payload, {
    String role = 'Member',
    Presence presence = Presence.offline,
    Set<String> spaceIds = const {},
    Map<String, String> rolesBySpace = const {},
    int? colorValue,
  }) {
    final username =
        payload['global_name'] as String? ??
        payload['username'] as String? ??
        'Unknown';
    final id = payload['id']! as String;
    return Member(
      id: id,
      displayName: username,
      initials: _monogram(username),
      role: role,
      presence: presence,
      colorValue: colorValue ?? _colorFor(id),
      spaceIds: spaceIds,
      rolesBySpace: rolesBySpace,
      avatarUrl: DiscordCdn.userAvatar(id, payload['avatar'] as String?),
    );
  }

  Member guildMember(
    Map<String, Object?> payload,
    String guildId,
    List<Map<String, Object?>> roles,
  ) {
    final user = (payload['user']! as Map).cast<String, Object?>();
    final roleIds = (payload['roles'] as List? ?? const []).whereType<String>();
    final matchingRoles =
        roles.where((role) => roleIds.contains(role['id'])).toList()..sort(
          (left, right) => (right['position'] as int? ?? 0).compareTo(
            left['position'] as int? ?? 0,
          ),
        );
    final topRole = matchingRoles.isEmpty ? null : matchingRoles.first;
    final roleName = topRole?['name'] as String? ?? 'Member';
    final roleColor = topRole?['color'] as int? ?? 0;
    final username =
        payload['nick'] as String? ??
        user['global_name'] as String? ??
        user['username'] as String? ??
        'Unknown';
    final id = user['id']! as String;
    final guildAvatarUrl = DiscordCdn.guildMemberAvatar(
      guildId,
      id,
      payload['avatar'] as String?,
    );
    return Member(
      id: id,
      displayName: username,
      initials: _monogram(username),
      role: roleName,
      presence: Presence.offline,
      colorValue: roleColor == 0 ? _colorFor(id) : 0xff000000 | roleColor,
      spaceIds: {guildId},
      rolesBySpace: {guildId: roleName},
      avatarUrl: DiscordCdn.userAvatar(id, user['avatar'] as String?),
      avatarUrlsBySpace: {guildId: ?guildAvatarUrl},
    );
  }

  Presence presence(String status) => switch (status) {
    'online' => Presence.online,
    'idle' || 'dnd' => Presence.idle,
    _ => Presence.offline,
  };

  CommunityRole role(Map<String, Object?> payload, String guildId) {
    final rawColor = payload['color'] as int? ?? 0;
    return CommunityRole(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'unknown-role',
      position: payload['position'] as int? ?? 0,
      colorValue: rawColor == 0 ? null : 0xff000000 | rawColor,
    );
  }

  ChannelCategory? category(Map<String, Object?> payload, String guildId) {
    if (payload['type'] != 4) return null;
    return ChannelCategory(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'Unnamed category',
      position: payload['position'] as int? ?? 0,
    );
  }

  static Member _mergeMembers(Member? previous, Member incoming) {
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

  CommunitySpace _space(Map<String, Object?> payload) {
    final name = payload['name'] as String? ?? 'Unnamed server';
    final id = payload['id']! as String;
    return CommunitySpace(
      id: id,
      name: name,
      monogram: _monogram(name),
      colorValue: _colorFor(id),
      iconUrl: DiscordCdn.guildIcon(id, payload['icon'] as String?),
    );
  }

  ConversationChannel? channel(Map<String, Object?> payload, String guildId) {
    final type = payload['type'] as int?;
    final kind = switch (type) {
      0 || 5 || 10 || 11 || 12 => ChannelKind.text,
      2 || 13 => ChannelKind.voice,
      _ => null,
    };
    if (kind == null) return null;
    return ConversationChannel(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'unnamed',
      topic:
          payload['topic'] as String? ??
          (kind == ChannelKind.voice ? 'Discord voice channel' : ''),
      kind: kind,
      position: payload['position'] as int? ?? 0,
      parentId: payload['parent_id'] as String?,
      isThread: type == 10 || type == 11 || type == 12,
      unread: false,
    );
  }

  static String _monogram(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .toList();
    if (words.isEmpty) return '?';
    return words.map((word) => word[0].toUpperCase()).join();
  }

  static int _colorFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _colors[hash % _colors.length];
  }
}
