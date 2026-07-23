import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/chat_cache.dart';
import '../domain/chat_models.dart';

final class SqliteChatCache implements ChatCache {
  SqliteChatCache._(this._database);

  final Database _database;

  static Future<SqliteChatCache> openDefault() async {
    sqfliteFfiInit();
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}database',
    );
    await databaseDirectory.create(recursive: true);
    return openAt(
      '${databaseDirectory.path}${Platform.pathSeparator}flucord.sqlite3',
    );
  }

  static Future<SqliteChatCache> openAt(
    String path, {
    DatabaseFactory? factory,
  }) async {
    sqfliteFfiInit();
    final database = await (factory ?? databaseFactoryFfi).openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );
    return SqliteChatCache._(database);
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE spaces (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        monogram TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        sort_index INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE channels (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        topic TEXT NOT NULL,
        kind INTEGER NOT NULL,
        unread INTEGER NOT NULL,
        mention_count INTEGER NOT NULL,
        sort_index INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        initials TEXT NOT NULL,
        role TEXT NOT NULL,
        presence INTEGER NOT NULL,
        color_value INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        author_id TEXT NOT NULL,
        body TEXT NOT NULL,
        sent_at TEXT NOT NULL,
        is_edited INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX messages_channel_time '
      'ON messages(channel_id, sent_at)',
    );
  }

  @override
  Future<ChatWorkspace?> readWorkspace() async {
    final metadata = await _database.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['current_member_id'],
      limit: 1,
    );
    final spaces = await _database.query('spaces', orderBy: 'sort_index');
    if (metadata.isEmpty || spaces.isEmpty) return null;
    final channels = await _database.query('channels', orderBy: 'sort_index');
    final members = await _database.query('members');
    final messages = await _database.query('messages', orderBy: 'sent_at');
    return ChatWorkspace(
      spaces: spaces.map(_spaceFromRow).toList(),
      channels: channels.map(_channelFromRow).toList(),
      members: members.map(_memberFromRow).toList(),
      messages: messages.map(_messageFromRow).toList(),
      currentMemberId: metadata.single['value']! as String,
    );
  }

  @override
  Future<void> writeWorkspace(ChatWorkspace workspace) async {
    await _database.transaction((transaction) async {
      await transaction.insert('metadata', {
        'key': 'current_member_id',
        'value': workspace.currentMemberId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete('spaces');
      await transaction.delete('channels');
      final batch = transaction.batch();
      for (var index = 0; index < workspace.spaces.length; index++) {
        batch.insert('spaces', _spaceToRow(workspace.spaces[index], index));
      }
      for (var index = 0; index < workspace.channels.length; index++) {
        batch.insert(
          'channels',
          _channelToRow(workspace.channels[index], index),
        );
      }
      for (final member in workspace.members) {
        batch.insert(
          'members',
          _memberToRow(member),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<ChannelHistory> readChannelHistory(String channelId) async {
    final messages = await _database.query(
      'messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'sent_at',
    );
    final authorIds = messages
        .map((row) => row['author_id']! as String)
        .toSet();
    final members = await _readMembers(authorIds);
    return ChannelHistory(
      channelId: channelId,
      messages: messages.map(_messageFromRow).toList(),
      members: members,
    );
  }

  @override
  Future<ChatMessage?> readMessage(String messageId) async {
    final rows = await _database.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return rows.isEmpty ? null : _messageFromRow(rows.single);
  }

  @override
  Future<void> writeChannelHistory(ChannelHistory history) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'messages',
        where: 'channel_id = ?',
        whereArgs: [history.channelId],
      );
      final batch = transaction.batch();
      for (final member in history.members) {
        batch.insert(
          'members',
          _memberToRow(member),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final message in history.messages) {
        batch.insert(
          'messages',
          _messageToRow(message),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> writeMessage(ChatMessage message, {Member? member}) async {
    await _database.transaction((transaction) async {
      if (member != null) {
        await transaction.insert(
          'members',
          _memberToRow(member),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await transaction.insert(
        'messages',
        _messageToRow(message),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<Member>> _readMembers(Set<String> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _database.query(
      'members',
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    return rows.map(_memberFromRow).toList();
  }

  static Map<String, Object> _spaceToRow(CommunitySpace space, int index) => {
    'id': space.id,
    'name': space.name,
    'monogram': space.monogram,
    'color_value': space.colorValue,
    'sort_index': index,
  };

  static CommunitySpace _spaceFromRow(Map<String, Object?> row) =>
      CommunitySpace(
        id: row['id']! as String,
        name: row['name']! as String,
        monogram: row['monogram']! as String,
        colorValue: row['color_value']! as int,
      );

  static Map<String, Object> _channelToRow(
    ConversationChannel channel,
    int index,
  ) => {
    'id': channel.id,
    'space_id': channel.spaceId,
    'name': channel.name,
    'topic': channel.topic,
    'kind': channel.kind.index,
    'unread': channel.unread ? 1 : 0,
    'mention_count': channel.mentionCount,
    'sort_index': index,
  };

  static ConversationChannel _channelFromRow(Map<String, Object?> row) =>
      ConversationChannel(
        id: row['id']! as String,
        spaceId: row['space_id']! as String,
        name: row['name']! as String,
        topic: row['topic']! as String,
        kind: ChannelKind.values[row['kind']! as int],
        unread: row['unread'] == 1,
        mentionCount: row['mention_count']! as int,
      );

  static Map<String, Object> _memberToRow(Member member) => {
    'id': member.id,
    'display_name': member.displayName,
    'initials': member.initials,
    'role': member.role,
    'presence': member.presence.index,
    'color_value': member.colorValue,
  };

  static Member _memberFromRow(Map<String, Object?> row) => Member(
    id: row['id']! as String,
    displayName: row['display_name']! as String,
    initials: row['initials']! as String,
    role: row['role']! as String,
    presence: Presence.values[row['presence']! as int],
    colorValue: row['color_value']! as int,
  );

  static Map<String, Object> _messageToRow(ChatMessage message) => {
    'id': message.id,
    'channel_id': message.channelId,
    'author_id': message.authorId,
    'body': message.body,
    'sent_at': message.sentAt.toUtc().toIso8601String(),
    'is_edited': message.isEdited ? 1 : 0,
  };

  static ChatMessage _messageFromRow(Map<String, Object?> row) => ChatMessage(
    id: row['id']! as String,
    channelId: row['channel_id']! as String,
    authorId: row['author_id']! as String,
    body: row['body']! as String,
    sentAt: DateTime.parse(row['sent_at']! as String).toLocal(),
    isEdited: row['is_edited'] == 1,
  );

  @override
  Future<void> close() => _database.close();
}
