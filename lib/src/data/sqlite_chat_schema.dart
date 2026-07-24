import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class SqliteChatSchema {
  static const version = 16;

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
        first_unread_message_id TEXT,
        parent_id TEXT,
        is_thread INTEGER NOT NULL,
        is_archived INTEGER NOT NULL,
        is_locked INTEGER NOT NULL,
        archive_timestamp TEXT,
        auto_archive_duration INTEGER,
        available_tags_json TEXT NOT NULL,
        applied_tag_ids_json TEXT NOT NULL,
        default_auto_archive_duration INTEGER,
        default_sort_order INTEGER,
        default_forum_layout INTEGER,
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
        embeds_json TEXT NOT NULL,
        mentions_current_member INTEGER NOT NULL,
        poll_json TEXT,
        stickers_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE emojis (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        image_url TEXT,
        animated INTEGER NOT NULL,
        available INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX emojis_space_name ON emojis(space_id, name)',
    );
    await _createGuildStickers(database);
    await _createGuildScheduledEvents(database);
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
    if (oldVersion < 9) {
      await database.execute(
        'ALTER TABLE channels ADD first_unread_message_id TEXT',
      );
    }
    if (oldVersion < 10) {
      await database.execute(
        'ALTER TABLE messages ADD mentions_current_member '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 11) {
      await database.execute('''
        CREATE TABLE emojis (
          id TEXT PRIMARY KEY,
          space_id TEXT NOT NULL,
          name TEXT NOT NULL,
          image_url TEXT,
          animated INTEGER NOT NULL,
          available INTEGER NOT NULL
        )
      ''');
      await database.execute(
        'CREATE INDEX emojis_space_name ON emojis(space_id, name)',
      );
    }
    if (oldVersion < 12) {
      await database.execute(
        'ALTER TABLE channels ADD is_archived INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE channels ADD is_locked INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute('ALTER TABLE channels ADD archive_timestamp TEXT');
      await database.execute(
        'ALTER TABLE channels ADD auto_archive_duration INTEGER',
      );
    }
    if (oldVersion < 13) {
      await database.execute(
        "ALTER TABLE channels ADD available_tags_json "
        "TEXT NOT NULL DEFAULT '[]'",
      );
      await database.execute(
        "ALTER TABLE channels ADD applied_tag_ids_json "
        "TEXT NOT NULL DEFAULT '[]'",
      );
      await database.execute(
        'ALTER TABLE channels ADD default_auto_archive_duration INTEGER',
      );
      await database.execute(
        'ALTER TABLE channels ADD default_sort_order INTEGER',
      );
      await database.execute(
        'ALTER TABLE channels ADD default_forum_layout INTEGER',
      );
    }
    if (oldVersion < 14) {
      await database.execute('ALTER TABLE messages ADD poll_json TEXT');
    }
    if (oldVersion < 15) {
      await database.execute(
        "ALTER TABLE messages ADD stickers_json TEXT NOT NULL DEFAULT '[]'",
      );
      await _createGuildStickers(database);
    }
    if (oldVersion < 16) {
      await _createGuildScheduledEvents(database);
    }
  }

  static Future<void> _createGuildStickers(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE guild_stickers (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        tags_json TEXT NOT NULL,
        format_type INTEGER NOT NULL,
        available INTEGER NOT NULL,
        url TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX guild_stickers_space_name '
      'ON guild_stickers(space_id, name)',
    );
  }

  static Future<void> _createGuildScheduledEvents(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE guild_scheduled_events (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        channel_id TEXT,
        name TEXT NOT NULL,
        description TEXT,
        location TEXT,
        scheduled_start_time TEXT NOT NULL,
        scheduled_end_time TEXT,
        entity_type INTEGER NOT NULL,
        status INTEGER NOT NULL,
        interested_count INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX guild_scheduled_events_space_start '
      'ON guild_scheduled_events(space_id, scheduled_start_time)',
    );
  }
}
