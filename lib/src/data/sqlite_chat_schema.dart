import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class SqliteChatSchema {
  static const version = 29;

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
        owner_id TEXT,
        requires_mfa INTEGER NOT NULL DEFAULT 0,
        premium_tier INTEGER NOT NULL DEFAULT 0,
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
        last_message_id TEXT,
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
        recipient_ids_json TEXT NOT NULL DEFAULT '[]',
        is_group_dm INTEGER NOT NULL DEFAULT 0,
        icon_url TEXT,
        is_message_request INTEGER NOT NULL DEFAULT 0,
        message_requested_at TEXT,
        permission_overwrites_json TEXT,
        rate_limit_per_user INTEGER NOT NULL DEFAULT 0,
        is_age_gated INTEGER NOT NULL DEFAULT 0,
        bitrate INTEGER,
        user_limit INTEGER,
        rtc_region TEXT,
        sort_index INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE roles (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        color_value INTEGER,
        permissions TEXT,
        hoist INTEGER NOT NULL DEFAULT 0
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
        avatar_url TEXT,
        avatar_urls_by_space_json TEXT NOT NULL,
        memberships_json TEXT,
        is_bot INTEGER NOT NULL DEFAULT 0,
        clan_tag_json TEXT,
        username TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        author_id TEXT NOT NULL,
        body TEXT NOT NULL,
        message_type INTEGER NOT NULL,
        reference_message_id TEXT,
        reference_channel_id TEXT,
        reference_guild_id TEXT,
        reference_type INTEGER NOT NULL,
        snapshots_json TEXT NOT NULL,
        flags INTEGER NOT NULL,
        sent_at TEXT NOT NULL,
        is_edited INTEGER NOT NULL,
        attachments_json TEXT NOT NULL,
        reply_json TEXT,
        reactions_json TEXT NOT NULL,
        is_pinned INTEGER NOT NULL,
        embeds_json TEXT NOT NULL,
        mentions_current_member INTEGER NOT NULL,
        poll_json TEXT,
        stickers_json TEXT NOT NULL,
        is_text_to_speech INTEGER NOT NULL DEFAULT 0,
        components_json TEXT NOT NULL DEFAULT '[]',
        mentions_everyone INTEGER NOT NULL DEFAULT 0
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
    if (oldVersion < 17) {
      await database.execute(
        'ALTER TABLE messages ADD message_type INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE messages ADD reference_message_id TEXT',
      );
      await database.execute(
        'ALTER TABLE messages ADD reference_channel_id TEXT',
      );
    }
    if (oldVersion < 18) {
      await database.execute(
        'ALTER TABLE messages ADD reference_guild_id TEXT',
      );
      await database.execute(
        'ALTER TABLE messages ADD reference_type INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        "ALTER TABLE messages ADD snapshots_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (oldVersion < 19) {
      await database.execute(
        'ALTER TABLE messages ADD flags INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 20) {
      // Every new permission column is nullable on purpose. A row written
      // before this version knows nothing about permissions, and null is how
      // the reader tells that apart from a role that really grants nothing.
      await _addColumn(database, 'spaces', 'owner_id TEXT');
      await _addColumn(
        database,
        'spaces',
        'requires_mfa INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(database, 'roles', 'permissions TEXT');
      await _addColumn(database, 'channels', 'permission_overwrites_json TEXT');
      await _addColumn(database, 'members', 'memberships_json TEXT');
    }
    if (oldVersion < 21) {
      // Unread is a comparison against this pointer, so an offline launch that
      // could not read it would report every channel read until the socket came
      // back. Nullable: a row written before this version simply has no answer.
      await _addColumn(database, 'channels', 'last_message_id TEXT');
    }
    if (oldVersion < 22) {
      // A channel's editor fields, cached so an offline launch still knows
      // what the composer owes a slowmode channel and the sidebar its age
      // gate. Defaults rather than nulls: a row written before this version
      // genuinely has no slowmode and no gate, which is what zero says.
      await _addColumn(
        database,
        'channels',
        'rate_limit_per_user INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(
        database,
        'channels',
        'is_age_gated INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(database, 'channels', 'bitrate INTEGER');
      await _addColumn(database, 'channels', 'user_limit INTEGER');
      await _addColumn(database, 'channels', 'rtc_region TEXT');
    }
    if (oldVersion < 23) {
      // Defaults rather than nulls: a row written before this version is a
      // message nobody spoke aloud and a server whose boost level this cache
      // never learned, which is what zero says for both.
      await _addColumn(
        database,
        'messages',
        'is_text_to_speech INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(
        database,
        'spaces',
        'premium_tier INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 24) {
      // A partial update fills its gaps from the cached message, so anything
      // the cache drops is lost at the next update. A row written before this
      // version gets its buttons back when Discord next sends the message.
      await _addColumn(
        database,
        'messages',
        "components_json TEXT NOT NULL DEFAULT '[]'",
      );
      await _addColumn(
        database,
        'messages',
        'mentions_everyone INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 25) {
      // A row written before this version is read as a person with no clan
      // tag. Both come back the next time Discord sends the user.
      await _addColumn(
        database,
        'members',
        'is_bot INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(database, 'members', 'clan_tag_json TEXT');
    }
    if (oldVersion < 26) {
      // A row written before this version reads as an answered DM. The next
      // READY says which ones are still requests, and the reconnect diff
      // moves them to the folder.
      await _addColumn(
        database,
        'channels',
        'is_message_request INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(database, 'channels', 'message_requested_at TEXT');
    }
    if (oldVersion < 27) {
      // A DM keeps every recipient, so a group DM fits. The old single
      // recipient moves into the list and its column is left unused; it is
      // nullable, so new rows simply leave it empty. Every row written before
      // this version is a one-to-one DM, which zero says.
      await _addColumn(
        database,
        'channels',
        "recipient_ids_json TEXT NOT NULL DEFAULT '[]'",
      );
      await _addColumn(
        database,
        'channels',
        'is_group_dm INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumn(database, 'channels', 'icon_url TEXT');
      if (await _hasTable(database, 'channels')) {
        await database.execute(
          "UPDATE channels SET recipient_ids_json = '[\"' || recipient_id || '\"]' "
          'WHERE recipient_id IS NOT NULL',
        );
      }
    }
    if (oldVersion < 28) {
      // A row written before this version has no username. It comes back the
      // next time Discord sends the user.
      await _addColumn(database, 'members', 'username TEXT');
    }
    if (oldVersion < 29) {
      // A role's name, place and grouping are read from the roles table by id,
      // so a member row no longer keeps a copy of its top role's name. A role
      // row written before this version reads as not hoisted until Discord
      // next sends the role.
      //
      // Step 27 leaves recipient_id in place, but this step drops the old
      // column. recipient_id is nullable, so new rows can leave it out. In a
      // database created before this version, roles_by_space_json is NOT NULL
      // with no default, so a new member row that leaves it out would fail.
      await _addColumn(database, 'roles', 'hoist INTEGER NOT NULL DEFAULT 0');
      await _dropColumn(database, 'members', 'roles_by_space_json');
    }
  }

  /// Adds a column, skipping tables this database does not have.
  ///
  /// A step that spans several tables cannot assume all of them survived every
  /// earlier version, and an upgrade that throws does not fail one query — it
  /// makes the cache impossible to open again, for good. Skipping a table that
  /// is not there costs nothing: a database without it has no rows to migrate.
  static Future<void> _addColumn(
    Database database,
    String table,
    String definition,
  ) async {
    if (!await _hasTable(database, table)) return;
    await database.execute('ALTER TABLE $table ADD $definition');
  }

  static Future<bool> _hasTable(Database database, String table) async {
    final existing = await database.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', table],
      limit: 1,
    );
    return existing.isNotEmpty;
  }

  /// Drops a column, skipping a table or a column this database does not
  /// have, for the reason [_addColumn] gives.
  static Future<void> _dropColumn(
    Database database,
    String table,
    String column,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) return;
    await database.execute('ALTER TABLE $table DROP COLUMN $column');
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
