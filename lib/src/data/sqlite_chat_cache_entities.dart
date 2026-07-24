part of 'sqlite_chat_cache.dart';

mixin _SqliteChatCacheEntities implements ChatCache {
  Database get _database;

  @override
  Future<void> writeMember(Member member) => _database.insert(
    'members',
    SqliteChatCache._memberToRow(member),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> writeCategory(ChannelCategory category) => _database.insert(
    'categories',
    SqliteChatCache._categoryToRow(category),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Map<String, Object?> _messageToRow(ChatMessage message) => {
  'id': message.id,
  'channel_id': message.channelId,
  'author_id': message.authorId,
  'body': message.body,
  'message_type': message.type.discordValue,
  'reference_message_id': message.reference?.messageId,
  'reference_channel_id': message.reference?.channelId,
  'reference_guild_id': message.reference?.guildId,
  'reference_type':
      message.reference?.type.discordValue ??
      DiscordMessageReferenceType.defaultReference.discordValue,
  'snapshots_json': MessageSnapshotCodec.encode(message.snapshots),
  'flags': message.flags,
  'sent_at': message.sentAt.toUtc().toIso8601String(),
  'is_edited': message.isEdited ? 1 : 0,
  'attachments_json': ChatModelJson.attachments(message.attachments),
  'reply_json': ChatModelJson.reply(message.reply),
  'reactions_json': ChatModelJson.reactions(message.reactions),
  'is_pinned': message.isPinned ? 1 : 0,
  'embeds_json': ChatModelJson.embeds(message.embeds),
  'mentions_current_member': message.mentionsCurrentMember ? 1 : 0,
  'poll_json': ChatModelJson.poll(message.poll),
  'stickers_json': ChatModelJson.stickers(message.stickers),
};

ChatMessage _messageFromRow(Map<String, Object?> row) => ChatMessage(
  id: row['id']! as String,
  channelId: row['channel_id']! as String,
  authorId: row['author_id']! as String,
  body: row['body']! as String,
  type: DiscordMessageType.fromDiscordValue(row['message_type'] as int?),
  reference:
      row['reference_message_id'] == null &&
          row['reference_channel_id'] == null &&
          row['reference_guild_id'] == null &&
          (row['reference_type'] == null ||
              row['reference_type'] ==
                  DiscordMessageReferenceType.defaultReference.discordValue)
      ? null
      : MessageReference(
          messageId: row['reference_message_id'] as String?,
          channelId: row['reference_channel_id'] as String?,
          guildId: row['reference_guild_id'] as String?,
          type: DiscordMessageReferenceType.fromDiscordValue(
            row['reference_type'] as int?,
          ),
        ),
  snapshots: MessageSnapshotCodec.decode(
    row['snapshots_json'] as String? ?? '[]',
  ),
  flags: row['flags'] as int? ?? 0,
  sentAt: DateTime.parse(row['sent_at']! as String).toLocal(),
  isEdited: row['is_edited'] == 1,
  attachments: ChatModelJson.attachmentsFrom(
    row['attachments_json']! as String,
  ),
  reply: ChatModelJson.replyFrom(row['reply_json'] as String?),
  reactions: ChatModelJson.reactionsFrom(row['reactions_json']! as String),
  isPinned: row['is_pinned'] == 1,
  embeds: ChatModelJson.embedsFrom(row['embeds_json']! as String),
  mentionsCurrentMember: row['mentions_current_member'] == 1,
  poll: ChatModelJson.pollFrom(row['poll_json'] as String?),
  stickers: ChatModelJson.stickersFrom(row['stickers_json']! as String),
);
