import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class SqliteChatSchema {
  static const version = 8;

  static Future<void> create(Database database, int version) async {
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
        icon_url TEXT,
        kind INTEGER NOT NULL,
        sort_index INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE channels (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        topic TEXT NOT NULL,
        kind INTEGER NOT NULL,
        position INTEGER NOT NULL,
        unread INTEGER NOT NULL,
        mention_count INTEGER NOT NULL,
        parent_id TEXT,
        is_thread INTEGER NOT NULL,
        recipient_id TEXT,
        sort_index INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE roles (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        color_value INTEGER
      )
    ''');
    await database.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        initials TEXT NOT NULL,
        role TEXT NOT NULL,
        presence INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        space_ids_json TEXT NOT NULL,
        roles_by_space_json TEXT NOT NULL,
        avatar_url TEXT,
        avatar_urls_by_space_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        author_id TEXT NOT NULL,
        body TEXT NOT NULL,
        sent_at TEXT NOT NULL,
        is_edited INTEGER NOT NULL,
        attachments_json TEXT NOT NULL,
        reply_json TEXT,
        reactions_json TEXT NOT NULL,
        is_pinned INTEGER NOT NULL,
        embeds_json TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX messages_channel_time '
      'ON messages(channel_id, sent_at)',
    );
  }

  static Future<void> upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute('ALTER TABLE channels ADD parent_id TEXT');
      await database.execute(
        'ALTER TABLE channels ADD is_thread INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        "ALTER TABLE messages ADD attachments_json TEXT NOT NULL DEFAULT '[]'",
      );
      await database.execute('ALTER TABLE messages ADD reply_json TEXT');
      await database.execute(
        "ALTER TABLE messages ADD reactions_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (oldVersion < 3) {
      await database.execute(
        "ALTER TABLE members ADD space_ids_json TEXT NOT NULL DEFAULT '[]'",
      );
      await database.execute(
        "ALTER TABLE members ADD roles_by_space_json TEXT NOT NULL DEFAULT '{}'",
      );
      await database.execute(
        'ALTER TABLE messages ADD is_pinned INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await database.execute('ALTER TABLE spaces ADD icon_url TEXT');
      await database.execute('ALTER TABLE members ADD avatar_url TEXT');
      await database.execute(
        "ALTER TABLE members ADD avatar_urls_by_space_json "
        "TEXT NOT NULL DEFAULT '{}'",
      );
    }
    if (oldVersion < 5) {
      await database.execute(
        "ALTER TABLE messages ADD embeds_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (oldVersion < 6) {
      await database.execute('''
        CREATE TABLE roles (
          id TEXT PRIMARY KEY,
          space_id TEXT NOT NULL,
          name TEXT NOT NULL,
          position INTEGER NOT NULL,
          color_value INTEGER
        )
      ''');
    }
    if (oldVersion < 7) {
      await database.execute(
        'ALTER TABLE spaces ADD kind INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute('ALTER TABLE channels ADD recipient_id TEXT');
    }
    if (oldVersion < 8) {
      await database.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          space_id TEXT NOT NULL,
          name TEXT NOT NULL,
          position INTEGER NOT NULL
        )
      ''');
      await database.execute(
        'ALTER TABLE channels ADD position INTEGER NOT NULL DEFAULT 0',
      );
    }
  }
}
