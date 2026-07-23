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
  }) {
    final spaces = <CommunitySpace>[];
    final channels = <ConversationChannel>[];
    for (final guild in guilds) {
      final guildId = guild['id']! as String;
      final mappedChannels = (channelsByGuild[guildId] ?? const [])
          .map((channel) => _channel(channel, guildId))
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
    final attachments = payload['attachments'];
    final body = rawContent.isNotEmpty
        ? rawContent
        : attachments is List && attachments.isNotEmpty
        ? '[Attachment]'
        : '[Message without text content]';
    return ChatMessage(
      id: payload['id'] as String? ?? fallback!.id,
      channelId: payload['channel_id'] as String? ?? fallback!.channelId,
      authorId: payload['author'] is Map
          ? (payload['author']! as Map)['id']! as String
          : fallback!.authorId,
      body: body,
      sentAt: payload['timestamp'] is String
          ? DateTime.parse(payload['timestamp']! as String).toLocal()
          : fallback!.sentAt,
      isEdited: payload.containsKey('edited_timestamp')
          ? payload['edited_timestamp'] != null
          : fallback?.isEdited ?? false,
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

  ConversationChannel? _channel(Map<String, Object?> payload, String guildId) {
    final type = payload['type'] as int?;
    final kind = switch (type) {
      0 || 5 => ChannelKind.text,
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
