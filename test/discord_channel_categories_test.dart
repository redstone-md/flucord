import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_channel_handler.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('maps documented categories, parents, and channel positions', () {
    final workspace = DiscordMapper().workspace(
      currentUser: {'id': 'bot-1', 'username': 'Flucord Bot'},
      guilds: const [
        {'id': 'guild-1', 'name': 'The Forge'},
      ],
      channelsByGuild: const {
        'guild-1': [
          {
            'id': 'category-1',
            'guild_id': 'guild-1',
            'name': 'Operations',
            'type': 4,
            'position': 1,
          },
          {
            'id': 'channel-1',
            'guild_id': 'guild-1',
            'name': 'alerts',
            'type': 0,
            'position': 3,
            'parent_id': 'category-1',
          },
        ],
      },
    );

    expect(workspace.categories.single.name, 'Operations');
    expect(workspace.categories.single.position, 1);
    expect(workspace.channels.single.parentId, 'category-1');
    expect(workspace.channels.single.position, 3);
  });

  test('reads a guild named inside its properties', () {
    final workspace = DiscordMapper().workspace(
      currentUser: {'id': 'me', 'username': 'Me'},
      // What a desktop session sends: the guild record split in two, with the
      // name and the icon inside `properties`. Reading only the top level drew
      // every server in the rail as "Unnamed server" with a blank badge.
      guilds: const [
        {
          'id': 'guild-1',
          'properties': {'id': 'guild-1', 'name': 'The Forge', 'icon': 'abc'},
        },
      ],
      channelsByGuild: const {
        'guild-1': [
          {'id': 'general', 'guild_id': 'guild-1', 'name': 'general', 'type': 0},
        ],
      },
    );

    expect(workspace.spaces.single.name, 'The Forge');
    expect(workspace.spaces.single.monogram, isNot('U'));
    expect(workspace.spaces.single.iconUrl, contains('abc'));
  });

  test('persists live category and child-channel changes', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    await cache.writeWorkspace(
      ChatWorkspace(
        spaces: const [
          CommunitySpace(
            id: 'guild-1',
            name: 'The Forge',
            monogram: 'TF',
            colorValue: 0xff456b5a,
          ),
        ],
        channels: const [],
        members: const [],
        messages: const [],
        currentMemberId: 'bot-1',
      ),
    );
    final handler = DiscordChannelHandler(cache, DiscordMapper());

    final categoryEvent = await handler.upsert(const {
      'id': 'category-1',
      'type': 4,
      'name': 'Operations',
      'position': 1,
    }, 'guild-1');
    final channelEvent = await handler.upsert(const {
      'id': 'channel-1',
      'type': 0,
      'name': 'alerts',
      'position': 2,
      'parent_id': 'category-1',
    }, 'guild-1');

    expect(categoryEvent, isA<CategoryUpsertedEvent>());
    expect(channelEvent, isA<ChannelUpsertedEvent>());
    var restored = await cache.readWorkspace();
    expect(restored?.categories.single.id, 'category-1');
    expect(restored?.channels.single.parentId, 'category-1');
    expect(restored?.channels.single.position, 2);

    final deleteEvent = await handler.delete(const {
      'id': 'category-1',
      'type': 4,
    });
    expect(deleteEvent, isA<CategoryDeletedEvent>());
    restored = await cache.readWorkspace();
    expect(restored?.categories, isEmpty);
  });
}
