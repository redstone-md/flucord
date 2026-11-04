part of 'sqlite_chat_cache.dart';

mixin _SqliteChatCacheEntities implements ChatCache {
  Database get _database;
  SqliteWriteQueue get _writes;

  @override
  Future<void> writeMember(Member member) => writeMembers([member]);

  @override
  Future<void> writeMembers(List<Member> members) async {
    if (members.isEmpty) return;
    _writes.add((transaction) => _layMembers(transaction, members));
  }

  @override
  Future<void> writeMemberIdentity(
    String memberId,
    MemberIdentity identity,
  ) async {
    _writes.add(
      (transaction) => transaction.update(
        'members',
        {
          'username': identity.username,
          ...SqliteChatCache._tagsToRow(identity.tags),
        },
        where: 'id = ?',
        whereArgs: [memberId],
      ),
    );
  }

  @override
  Future<void> writeCategory(ChannelCategory category) => _database.insert(
    'categories',
    SqliteChatCache._categoryToRow(category),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// Writes [members] laid over the rows held for them, as [Member.over] lays
/// them. A payload names only part of what is known of somebody, so the
/// spaces, memberships and server avatars it leaves out keep their values.
Future<void> _layMembers(
  DatabaseExecutor executor,
  Iterable<Member> members,
) async {
  final incoming = <String, Member>{};
  for (final member in members) {
    final earlier = incoming[member.id];
    incoming[member.id] = earlier == null ? member : member.over(earlier);
  }
  if (incoming.isEmpty) return;
  final held = {
    for (final member in await _readMembersIn(executor, incoming.keys))
      member.id: member,
  };
  final batch = executor.batch();
  for (final member in incoming.values) {
    final known = held[member.id];
    _MemberUpsert(known == null ? member : member.over(known)).addTo(batch);
  }
  await batch.commit(noResult: true);
}

/// The member rows held for [ids]. Read in slices, as SQLite caps how many
/// values one statement may bind.
Future<List<Member>> _readMembersIn(
  DatabaseExecutor executor,
  Iterable<String> ids,
) async {
  const slice = 500;
  final all = ids.toList(growable: false);
  return [
    for (var start = 0; start < all.length; start += slice)
      for (final row in await executor.query(
        'members',
        where:
            'id IN (${List.filled(min(slice, all.length - start), '?').join(',')})',
        whereArgs: all.sublist(start, min(start + slice, all.length)),
      ))
        SqliteChatCache._memberFromRow(row),
  ];
}

/// Writes one member row: a new row whole, a held one with only the columns
/// the member knows. Unlike a replace, a column left out keeps its value.
final class _MemberUpsert {
  _MemberUpsert(Member member) : _row = SqliteChatCache._memberToRow(member);

  final Map<String, Object?> _row;

  String get _sql {
    final columns = _row.keys.toList(growable: false);
    final updates = columns
        .where((column) => column != 'id')
        .map((column) => '$column = excluded.$column')
        .join(', ');
    return 'INSERT INTO members (${columns.join(', ')}) '
        'VALUES (${List.filled(columns.length, '?').join(', ')}) '
        'ON CONFLICT(id) DO UPDATE SET $updates';
  }

  Future<void> run(DatabaseExecutor executor) =>
      executor.rawInsert(_sql, _row.values.toList(growable: false));

  void addTo(Batch batch) =>
      batch.rawInsert(_sql, _row.values.toList(growable: false));
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
  'is_text_to_speech': message.isTextToSpeech ? 1 : 0,
  'components_json': ChatModelJson.componentRows(message.componentRows),
  'mentions_everyone': message.mentionsEveryone ? 1 : 0,
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
  isTextToSpeech: row['is_text_to_speech'] == 1,
  componentRows: ChatModelJson.componentRowsFrom(
    row['components_json']! as String,
  ),
  mentionsEveryone: row['mentions_everyone'] == 1,
);
