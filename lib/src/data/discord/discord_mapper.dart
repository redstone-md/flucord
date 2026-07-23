import '../../domain/chat_models.dart';

final class DiscordMapper {
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
  }) {
    final spaces = <CommunitySpace>[];
    final channels = <ConversationChannel>[];
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
    }
    final currentMember = member(currentUser, role: 'Discord bot');
    return ChatWorkspace(
      spaces: spaces,
      channels: channels,
      members: [currentMember],
      messages: const [],
      currentMemberId: currentMember.id,
    );
  }

  ChannelHistory history(
    String channelId,
    List<Map<String, Object?>> payloads,
  ) {
    final members = <String, Member>{};
    final messages = <ChatMessage>[];
    for (final payload in payloads.reversed) {
      final authorPayload = (payload['author']! as Map).cast<String, Object?>();
      final author = member(authorPayload);
      members[author.id] = author;
      messages.add(message(payload));
    }
    return ChannelHistory(
      channelId: channelId,
      messages: messages,
      members: members.values.toList(),
    );
  }

  ChatMessage message(Map<String, Object?> payload, {ChatMessage? fallback}) {
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
      attachments: attachments,
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

  Member member(Map<String, Object?> payload, {String role = 'Member'}) {
    final username =
        payload['global_name'] as String? ??
        payload['username'] as String? ??
        'Unknown';
    return Member(
      id: payload['id']! as String,
      displayName: username,
      initials: _monogram(username),
      role: role,
      presence: Presence.online,
      colorValue: _colorFor(payload['id']! as String),
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
