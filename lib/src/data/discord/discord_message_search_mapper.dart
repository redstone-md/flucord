part of 'discord_mapper.dart';

extension DiscordMessageSearchMapper on DiscordMapper {
  /// Maps one classic search envelope.
  ///
  /// [fallbackSpaceId] names the guild a returned channel belongs to when the
  /// payload does not say so itself, which is the case for the channel-scoped
  /// route: it answers about one channel and never repeats its guild.
  ///
  /// The envelope's `members` array is deliberately ignored. Despite the name
  /// those are *thread* members — `{id, user_id, flags, muted, mute_config,
  /// join_timestamp}` — and feeding them through the guild-member mapper would
  /// write rows with a thread id where a user id belongs. The authors the
  /// results panel actually needs come off each message's own `author` object.
  MessageSearchResults searchResults(
    Map<String, Object?> payload, {
    String? currentMemberId,
    String? fallbackSpaceId,
  }) {
    final authors = <String, Member>{};
    final groups = <MessageSearchHitGroup>[];
    for (final rawGroup in _listOf(payload['messages'])) {
      if (rawGroup is! List) continue;
      final group = _hitGroup(
        rawGroup,
        authors: authors,
        currentMemberId: currentMemberId,
      );
      if (group != null) groups.add(group);
    }
    return MessageSearchResults(
      totalResults: payload['total_results'] as int? ?? 0,
      groups: groups,
      authors: authors.values.toList(growable: false),
      channels: _searchChannels(payload, fallbackSpaceId),
      analyticsId: payload['analytics_id'] as String?,
      doingDeepHistoricalIndex: payload['doing_deep_historical_index'] == true,
      documentsIndexed: payload['documents_indexed'] as int? ?? 0,
    );
  }

  /// One element of `messages`, which is an array of whole message objects
  /// rather than a single message: a hit travels with the conversation around
  /// it. The match is the first element flagged `hit`, and only when no element
  /// carries the flag does the first message stand in — the position of the hit
  /// inside a group is not established, so it is never assumed.
  MessageSearchHitGroup? _hitGroup(
    List<Object?> rawGroup, {
    required Map<String, Member> authors,
    String? currentMemberId,
  }) {
    final messages = <ChatMessage>[];
    var hitIndex = -1;
    for (final raw in rawGroup) {
      if (raw is! Map) continue;
      final message = raw.cast<String, Object?>();
      final author = message['author'];
      // Search answers with whole message objects, so anything missing the
      // fields a message is built from is a payload this mapper cannot honour
      // — and reaching for a fallback that does not exist would throw.
      if (message['id'] is! String ||
          message['channel_id'] is! String ||
          message['timestamp'] is! String ||
          author is! Map) {
        continue;
      }
      if (hitIndex < 0 && message['hit'] == true) hitIndex = messages.length;
      messages.add(this.message(message, currentMemberId: currentMemberId));
      final mapped = member(author.cast<String, Object?>());
      authors[mapped.id] = mapped;
    }
    if (messages.isEmpty) return null;
    return MessageSearchHitGroup(
      messages: messages,
      hitIndex: hitIndex < 0 ? 0 : hitIndex,
    );
  }

  /// `channels` and `threads` both carry raw channel objects and are read the
  /// same way; a thread is only a channel whose parent happens to be one.
  List<ConversationChannel> _searchChannels(
    Map<String, Object?> payload,
    String? fallbackSpaceId,
  ) {
    final channels = <String, ConversationChannel>{};
    for (final key in const ['channels', 'threads']) {
      for (final raw in _listOf(payload[key])) {
        if (raw is! Map) continue;
        final channelPayload = raw.cast<String, Object?>();
        if (channelPayload['id'] is! String) continue;
        final spaceId =
            channelPayload['guild_id'] as String? ?? fallbackSpaceId;
        if (spaceId == null) continue;
        final mapped = channel(channelPayload, spaceId);
        if (mapped != null) channels[mapped.id] = mapped;
      }
    }
    return channels.values.toList(growable: false);
  }

  List<Object?> _listOf(Object? value) => value is List ? value : const [];
}
