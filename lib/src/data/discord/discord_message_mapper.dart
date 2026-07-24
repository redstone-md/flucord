part of 'discord_mapper.dart';

extension DiscordMessageMapper on DiscordMapper {
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
    final poll = payload.containsKey('poll')
        ? _mapPoll(payload['poll'])
        : fallback?.poll;
    final stickers = payload.containsKey('sticker_items')
        ? _mapStickerItems(payload['sticker_items'])
        : fallback?.stickers ?? const [];
    final referenced = payload['referenced_message'];
    final reply = referenced is Map
        ? _reply(referenced.cast<String, Object?>())
        : fallback?.reply;
    final rawReference = payload['message_reference'];
    final reference = rawReference is Map
        ? MessageReference(
            messageId: rawReference['message_id'] as String?,
            channelId: rawReference['channel_id'] as String?,
            guildId: rawReference['guild_id'] as String?,
            type: DiscordMessageReferenceType.fromDiscordValue(
              rawReference['type'] as int?,
            ),
          )
        : fallback?.reference;
    final snapshots = payload.containsKey('message_snapshots')
        ? _mapMessageSnapshots(payload['message_snapshots'])
        : fallback?.snapshots ?? const <MessageSnapshot>[];
    final type = payload.containsKey('type')
        ? DiscordMessageType.fromDiscordValue(payload['type'] as int?)
        : fallback?.type ?? DiscordMessageType.defaultMessage;
    final flags = payload.containsKey('flags')
        ? payload['flags'] as int? ?? 0
        : fallback?.flags ?? 0;
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
      stickers: stickers,
      poll: poll,
      reply: reply,
      reference: reference,
      snapshots: snapshots,
      type: type,
      flags: flags,
    );
  }
}
