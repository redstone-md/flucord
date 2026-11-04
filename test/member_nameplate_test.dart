import 'dart:io';

import 'package:flucord/src/data/discord/discord_cdn.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _userId = '100000000000000002';

const _twilight = {
  'asset': 'nameplates/nameplates/twilight/',
  'palette': 'bubble_gum',
  'sku_id': '1349849614353829990',
  'label': 'COLLECTIBLES_NAMEPLATES_TWILIGHT_A11Y',
};

const _gradient = {
  'colors': [16711680, 255],
  'font_id': 11,
  'effect_id': 2,
};

Map<String, Object?> _user([Map<String, Object?> extra = const {}]) => {
  'id': _userId,
  'username': 'freezz5126',
  'global_name': 'Freez',
  ...extra,
};

Member _freez(MemberTags tags) => Member(
  id: _userId,
  displayName: 'Freez',
  initials: 'F',
  role: 'Member',
  presence: Presence.offline,
  colorValue: 0xff456b5a,
  tags: tags,
);

ChatWorkspace _workspaceWith(Member member) => ChatWorkspace(
  spaces: const [],
  channels: const [],
  members: [member],
  messages: const [],
  currentMemberId: 'me',
);

ChatMessage _message() => ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: _userId,
  body: 'hi',
  sentAt: DateTime.utc(2026, 11, 4, 8),
);

/// A user's nameplate and display name style ride on every user object and
/// are kept on the member like the clan tag: absent keeps, null clears.
void main() {
  setUpAll(sqfliteFfiInit);
  final mapper = DiscordMapper();

  group('reading a user object', () {
    test('keeps the nameplate and the name style it carries', () {
      final member = mapper.member(
        _user({
          'collectibles': {'nameplate': _twilight},
          'display_name_styles': _gradient,
        }),
      );

      expect(
        member.tags.nameplate,
        const Nameplate(
          asset: 'nameplates/nameplates/twilight/',
          palette: NameplatePalette.bubbleGum,
        ),
      );
      expect(
        member.tags.nameStyle,
        const NameStyle(
          colors: [0xffff0000, 0xff0000ff],
          fontId: 11,
          effectId: 2,
        ),
      );
    });

    test('a name colour keeps only its 24 colour bits', () {
      final member = mapper.member(
        _user({
          'display_name_styles': {
            'colors': [0x1005865f2],
          },
        }),
      );

      expect(member.tags.nameStyle?.colors, [0xff5865f2]);
    });

    test('a palette this client does not know draws no wash', () {
      final member = mapper.member(
        _user({
          'collectibles': {
            'nameplate': {..._twilight, 'palette': 'placeholder'},
          },
        }),
      );

      expect(member.tags.nameplate?.palette, isNull);
      expect(member.tags.nameplate?.asset, 'nameplates/nameplates/twilight/');
    });

    test('a user object that leaves both out keeps the known ones', () {
      final known = _workspaceWith(
        mapper.member(
          _user({
            'collectibles': {'nameplate': _twilight},
            'display_name_styles': _gradient,
          }),
        ),
      );

      final merged = known.upsertMember(mapper.member(_user()));
      final tags = merged.memberOrNull(_userId)!.tags;

      expect(tags.nameplate?.asset, 'nameplates/nameplates/twilight/');
      expect(tags.nameStyle?.effectId, 2);
    });

    test('an explicit null clears both', () {
      final known = _workspaceWith(
        mapper.member(
          _user({
            'collectibles': {'nameplate': _twilight},
            'display_name_styles': _gradient,
          }),
        ),
      );

      final merged = known.upsertMember(
        mapper.member(_user({'collectibles': null, 'display_name_styles': null})),
      );
      final tags = merged.memberOrNull(_userId)!.tags;

      expect(tags.nameplate, isNull);
      expect(tags.nameStyle, isNull);
    });

    test('collectibles without a nameplate clear the nameplate', () {
      final known = _workspaceWith(
        mapper.member(_user({'collectibles': {'nameplate': _twilight}})),
      );

      final merged = known.upsertMember(
        mapper.member(_user({'collectibles': <String, Object?>{}})),
      );

      expect(merged.memberOrNull(_userId)!.tags.nameplate, isNull);
    });

    test('a presence user with a username carries them as identity', () {
      final identity = mapper.identity(
        _user({'collectibles': {'nameplate': _twilight}}),
      )!;

      final updated = _freez(MemberTags.none).withIdentity(identity);

      expect(updated.tags.nameplate?.palette, NameplatePalette.bubbleGum);
    });
  });

  test('the still picture of a nameplate comes from the collectibles CDN', () {
    expect(
      DiscordCdn.nameplate('nameplates/nameplates/twilight/'),
      'https://cdn.discordapp.com/assets/collectibles/nameplates/nameplates/twilight/static.png',
    );
    expect(DiscordCdn.nameplate(''), isNull);
  });

  test('the moving nameplate sits next to the still one', () {
    expect(
      DiscordCdn.movingNameplate('nameplates/nameplates/twilight'),
      'https://cdn.discordapp.com/assets/collectibles/nameplates/nameplates/twilight/asset.webm',
    );
    expect(DiscordCdn.movingNameplate(''), isNull);
  });

  group('the cache', () {
    test('keeps the nameplate and the name style', () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);

      await cache.writeMessage(
        _message(),
        member: _freez(
          const MemberTags(
            nameplate: Nameplate(
              asset: 'nameplates/nameplates/twilight/',
              palette: NameplatePalette.cobalt,
            ),
            nameStyle: NameStyle(
              colors: [0xffff0000, 0xff0000ff],
              fontId: 3,
              effectId: 2,
            ),
          ),
        ),
      );
      await cache.writeMember(
        _freez(
          const MemberTags(
            unsaid: {TagPart.clanTag, TagPart.nameplate, TagPart.nameStyle},
          ),
        ),
      );
      final restored = (await cache.readChannelHistory('channel-1')).members;

      final tags = restored.single.tags;
      expect(tags.nameplate?.asset, 'nameplates/nameplates/twilight/');
      expect(tags.nameplate?.palette, NameplatePalette.cobalt);
      expect(tags.nameStyle?.colors, [0xffff0000, 0xff0000ff]);
      expect(tags.nameStyle?.fontId, 3);
      expect(tags.nameStyle?.effectId, 2);
    });

    test('a member cached before v30 opens with neither', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-member-nameplate-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 29,
          onCreate: (database, _) async {
            await database.execute(_v29Members);
            await database.execute(_v29Messages);
          },
        ),
      );
      await legacy.insert('members', {
        'id': _userId,
        'display_name': 'Freez',
        'initials': 'F',
        'role': 'Member',
        'presence': Presence.offline.index,
        'color_value': 0xff456b5a,
        'space_ids_json': '[]',
        'avatar_urls_by_space_json': '{}',
      });
      await legacy.insert('messages', {
        'id': 'message-1',
        'channel_id': 'channel-1',
        'author_id': _userId,
        'body': 'Before nameplates',
        'message_type': 0,
        'reference_type': 0,
        'snapshots_json': '[]',
        'flags': 0,
        'sent_at': DateTime.utc(2026, 11, 3).toIso8601String(),
        'is_edited': 0,
        'attachments_json': '[]',
        'reactions_json': '[]',
        'is_pinned': 0,
        'embeds_json': '[]',
        'mentions_current_member': 0,
        'stickers_json': '[]',
      });
      await legacy.close();

      final cache = await SqliteChatCache.openAt(
        path,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      final member = (await cache.readChannelHistory(
        'channel-1',
      )).members.single;

      expect(member.displayName, 'Freez');
      expect(member.tags.nameplate, isNull);
      expect(member.tags.nameStyle, isNull);
    });
  });
}

const _v29Members = '''
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
''';

const _v29Messages = '''
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
''';
