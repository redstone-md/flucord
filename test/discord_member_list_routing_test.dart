import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_member_list_directory.dart';
import 'package:flucord/src/data/discord/discord_member_list_handler.dart';
import 'package:flucord/src/data/discord/discord_murmur3.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> channel(
    String id, {
    int type = 0,
    String? memberListId,
    String? parentId,
    List<Map<String, Object?>> overwrites = const [],
  }) => {
    'id': id,
    'type': type,
    'member_list_id': ?memberListId,
    'parent_id': ?parentId,
    'permission_overwrites': overwrites,
  };

  Map<String, Object?> guild({
    String id = 'guild-1',
    Object? permissions = '1024',
    List<Map<String, Object?>> channels = const [],
    List<Map<String, Object?>> threads = const [],
    List<Map<String, Object?>> roles = const [],
  }) => {
    'id': id,
    'roles': [
      {'id': id, 'name': '@everyone', 'permissions': permissions},
      ...roles,
    ],
    'channels': channels,
    'threads': threads,
  };

  Map<String, Object?> memberItem(
    String userId, {
    String? status,
    List<String> roles = const [],
  }) => {
    'member': {
      'user': {'id': userId, 'username': 'user-$userId'},
      'roles': roles,
      if (status != null)
        'presence': {'status': status, 'user': <String, Object?>{}},
    },
  };

  group('member list directory', () {
    test('resolves everyone when the default role can read the channel', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(guild(channels: [channel('channel-1')]));

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        'everyone',
      );
      expect(directory.guildIds, ['guild-1']);
      expect(directory.rolesOf('guild-1').single['name'], '@everyone');
    });

    test('prefers a server supplied member list id', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(
          guild(
            permissions: 0,
            channels: [channel('channel-1', memberListId: '3141592653')],
          ),
        );

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        '3141592653',
      );
    });

    test('hashes the overwrites of a channel everyone cannot read', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(
          guild(
            permissions: 1024,
            channels: [
              channel(
                'channel-1',
                overwrites: [
                  {'id': 'role-a', 'allow': '0', 'deny': '1024'},
                ],
              ),
            ],
          ),
        );

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        '${DiscordMurmur3.hashText('deny:role-a')}',
      );
    });

    test(
      'resolves a thread through the parent it inherits visibility from',
      () {
        final directory = DiscordMemberListDirectory()
          ..acceptGuild(
            guild(
              permissions: '0',
              channels: [
                channel(
                  'parent-1',
                  overwrites: [
                    {'id': 'role-a', 'allow': '1024', 'deny': '0'},
                  ],
                ),
              ],
              threads: [channel('thread-1', type: 11, parentId: 'parent-1')],
            ),
          );

        expect(
          directory.memberListIdFor(guildId: 'guild-1', channelId: 'thread-1'),
          '${DiscordMurmur3.hashText('allow:role-a')}',
        );
      },
    );

    test('never resolves a private thread to everyone', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(
          guild(
            channels: [channel('parent-1')],
            threads: [channel('thread-1', type: 12, parentId: 'parent-1')],
          ),
        );

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'thread-1'),
        '${DiscordMurmur3.hashText('')}',
      );
    });

    test('falls back to the thread itself when the parent is unknown', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(
          guild(
            permissions: 1024,
            threads: [
              channel(
                'thread-1',
                type: 10,
                parentId: 'missing',
                overwrites: [
                  {'id': 'role-a', 'allow': '0', 'deny': '1024'},
                ],
              ),
              // A thread with no parent id keeps its own record as well.
              channel(
                'thread-2',
                type: 11,
                overwrites: [
                  {'id': 'role-b', 'allow': '0', 'deny': '1024'},
                ],
              ),
            ],
          ),
        );

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'thread-1'),
        '${DiscordMurmur3.hashText('deny:role-a')}',
      );
      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'thread-2'),
        '${DiscordMurmur3.hashText('deny:role-b')}',
      );
    });

    test('falls back to everyone for an unknown guild or channel', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(guild(permissions: 0, channels: [channel('channel-1')]));

      expect(
        directory.memberListIdFor(guildId: 'other', channelId: 'channel-1'),
        'everyone',
      );
      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'missing'),
        'everyone',
      );
    });

    test('a replayed READY drops guilds the account no longer has', () {
      final directory = DiscordMemberListDirectory()
        ..acceptReady({
          'guilds': [
            guild(permissions: 0, channels: [channel('channel-1')]),
            guild(id: 'guild-2'),
          ],
        })
        ..acceptReady({
          'guilds': [guild(id: 'guild-2')],
        });

      expect(directory.guildIds, ['guild-2']);
      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        'everyone',
      );
    });

    test('ignores payloads it cannot read', () {
      final directory = DiscordMemberListDirectory()
        ..acceptReady(const {'guilds': 'not-a-list'})
        ..acceptGuild(const {'id': 42})
        ..acceptGuild({
          'id': 'guild-1',
          'roles': 'not-a-list',
          'channels': [
            {'id': 7},
            'nonsense',
            channel('channel-1'),
          ],
          'threads': null,
        });

      expect(directory.guildIds, ['guild-1']);
      expect(directory.rolesOf('guild-1'), isEmpty);
      expect(directory.rolesOf('missing'), isEmpty);
      // No readable `@everyone` permissions means the channel is not public.
      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        '${DiscordMurmur3.hashText('')}',
      );
    });

    test('treats unparsable permissions as none', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(
          guild(permissions: 'not-a-number', channels: [channel('channel-1')]),
        );

      expect(
        directory.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        '${DiscordMurmur3.hashText('')}',
      );
    });

    test('forgets guilds on request', () {
      final directory = DiscordMemberListDirectory()
        ..acceptGuild(guild())
        ..acceptGuild(guild(id: 'guild-2'))
        ..removeGuild('guild-1');

      expect(directory.guildIds, ['guild-2']);
      directory.clear();
      expect(directory.guildIds, isEmpty);
    });
  });

  group('member list handler', () {
    Map<String, Object?> listUpdate({
      String guildId = 'guild-1',
      String listId = 'everyone',
      List<Map<String, Object?>> items = const [],
      List<Map<String, Object?>> groups = const [
        {'id': 'online', 'count': 1},
      ],
    }) => {
      'guild_id': guildId,
      'id': listId,
      'ops': [
        {
          'op': 'SYNC',
          'range': [0, items.length],
          'items': [
            {
              'group': {'id': 'online', 'count': items.length},
            },
            ...items,
          ],
        },
      ],
      'groups': groups,
      'member_count': 12,
      'online_count': 4,
    };

    test('applies a roster update and publishes the list', () async {
      final handler = DiscordMemberListHandler(DiscordMapper());
      addTearDown(handler.close);
      handler.accept('READY', {
        'guilds': [
          guild(
            channels: [channel('channel-1')],
            roles: [
              {
                'id': 'role-a',
                'name': 'Architects',
                'position': 5,
                'color': 0x48745f,
              },
            ],
          ),
        ],
      });
      final published = <GuildMemberList>[];
      handler.updates.listen(published.add);

      final members = handler.accept(
        'GUILD_MEMBER_LIST_UPDATE',
        listUpdate(
          items: [
            memberItem(
              '111111111111111111',
              status: 'online',
              roles: ['role-a'],
            ),
            memberItem('222222222222222222'),
          ],
          groups: const [
            {'id': 'online', 'count': 2},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(members.map((member) => member.id), [
        '111111111111111111',
        '222222222222222222',
      ]);
      expect(members.first.presence, Presence.online);
      expect(members.first.role, 'Architects');
      // No presence in the item leaves the member where the mapper puts it.
      expect(members.last.presence, Presence.offline);
      expect(published.single.rows, hasLength(3));
      expect(published.single.memberCount, 12);
      expect(
        handler.listFor(guildId: 'guild-1', listId: 'everyone')?.onlineCount,
        4,
      );
      expect(
        handler.memberListIdFor(guildId: 'guild-1', channelId: 'channel-1'),
        'everyone',
      );
    });

    test('a new session drops every cached roster', () {
      final handler = DiscordMemberListHandler(DiscordMapper());
      addTearDown(handler.close);
      handler
        ..accept('GUILD_MEMBER_LIST_UPDATE', listUpdate())
        ..accept('READY', const {});

      expect(handler.listFor(guildId: 'guild-1', listId: 'everyone'), isNull);
    });

    test('a guild leaving takes its rosters and channels with it', () {
      final handler = DiscordMemberListHandler(DiscordMapper());
      addTearDown(handler.close);
      handler
        ..accept(
          'GUILD_CREATE',
          guild(permissions: 0, channels: [channel('c')]),
        )
        ..accept('GUILD_MEMBER_LIST_UPDATE', listUpdate())
        ..accept('GUILD_DELETE', const {'id': 7})
        ..accept('GUILD_DELETE', const {'id': 'guild-1'});

      expect(handler.listFor(guildId: 'guild-1', listId: 'everyone'), isNull);
      expect(
        handler.memberListIdFor(guildId: 'guild-1', channelId: 'c'),
        'everyone',
      );
    });

    test('ignores dispatches it has no roster meaning for', () {
      final handler = DiscordMemberListHandler(DiscordMapper());
      addTearDown(handler.close);

      expect(handler.accept('MESSAGE_CREATE', const {}), isEmpty);
      expect(
        handler.accept('GUILD_MEMBER_LIST_UPDATE', const {'id': 'everyone'}),
        isEmpty,
      );
      expect(handler.listFor(guildId: 'guild-1', listId: 'everyone'), isNull);
    });

    test('a closed handler stops publishing', () async {
      final handler = DiscordMemberListHandler(DiscordMapper());
      await handler.close();

      expect(handler.accept('GUILD_MEMBER_LIST_UPDATE', listUpdate()), isEmpty);
      expect(handler.listFor(guildId: 'guild-1', listId: 'everyone'), isNull);
    });
  });
}
