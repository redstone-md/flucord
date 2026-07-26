import 'package:flucord/src/data/discord/discord_guild_subscriptions.dart';
import 'package:flucord/src/data/discord/discord_member_list_id.dart';
import 'package:flucord/src/data/discord/discord_member_list_ranges.dart';
import 'package:flucord/src/data/discord/discord_member_list_store.dart';
import 'package:flucord/src/data/discord/discord_member_list_update.dart';
import 'package:flucord/src/data/discord/discord_murmur3.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MurmurHash3 x86 32', () {
    test('matches the reference implementation', () {
      // Values produced by the mmh3 reference package with seed 0, covering
      // every tail length and multi-byte UTF-8.
      const vectors = <String, int>{
        '': 0,
        'a': 1009084850,
        'ab': 2613040991,
        'abc': 3017643002,
        'abcd': 1139631978,
        'abcde': 3902511862,
        'hello': 613153351,
        'everyone': 2205475881,
        'allow:123456789012345678': 942410588,
        'deny:123456789012345678': 1252621309,
        'The quick brown fox jumps over the lazy dog': 776992547,
        'héllo-🌍-üñïçødé': 3316759367,
      };

      vectors.forEach((input, expected) {
        expect(DiscordMurmur3.hashText(input), expected, reason: input);
      });
    });

    test('honours a non-zero seed and raw byte input', () {
      expect(
        DiscordMurmur3.hashBytes(const [104, 105], seed: 7),
        DiscordMurmur3.hashText('hi', seed: 7),
      );
      expect(
        DiscordMurmur3.hashText('hi', seed: 7),
        isNot(DiscordMurmur3.hashText('hi')),
      );
    });
  });

  group('member list id', () {
    Map<String, Object?> channel(List<Map<String, Object?>> overwrites) => {
      'id': 'channel',
      'permission_overwrites': overwrites,
    };

    final open = BigInt.from(1) << 10;

    test('falls back to everyone without a channel', () {
      expect(
        DiscordMemberListId.resolve(
          channel: null,
          everyoneRolePermissions: BigInt.zero,
        ),
        'everyone',
      );
    });

    test('prefers a server supplied identifier', () {
      expect(
        DiscordMemberListId.resolve(
          channel: {'member_list_id': '3141592653'},
          everyoneRolePermissions: open,
        ),
        '3141592653',
      );
    });

    test('uses everyone when the default role can read the channel', () {
      expect(
        DiscordMemberListId.resolve(
          channel: channel(const []),
          everyoneRolePermissions: open,
        ),
        'everyone',
      );
    });

    test('hashes when the default role cannot read the channel', () {
      expect(
        DiscordMemberListId.resolve(
          channel: channel(const []),
          everyoneRolePermissions: BigInt.zero,
        ),
        '${DiscordMurmur3.hashText('')}',
      );
    });

    test('hashes when an overwrite denies the default role', () {
      final id = DiscordMemberListId.resolve(
        channel: channel([
          {'id': '111111111111111111', 'allow': '0', 'deny': '1024'},
        ]),
        everyoneRolePermissions: open,
      );

      expect(id, '${DiscordMurmur3.hashText('deny:111111111111111111')}');
    });

    test('sorts tokens and prefers allow over deny on one overwrite', () {
      final id = DiscordMemberListId.resolve(
        channel: channel([
          {'id': '222222222222222222', 'allow': 0, 'deny': 1024},
          {'id': '111111111111111111', 'allow': 1024, 'deny': 1024},
          {'id': '333333333333333333', 'allow': 0, 'deny': 0},
        ]),
        everyoneRolePermissions: BigInt.zero,
      );

      expect(
        id,
        '${DiscordMurmur3.hashText('allow:111111111111111111,deny:222222222222222222')}',
      );
    });

    test('never treats a private thread as readable by everyone', () {
      expect(
        DiscordMemberListId.resolve(
          channel: channel(const []),
          everyoneRolePermissions: open,
          isPrivateThread: true,
        ),
        isNot('everyone'),
      );
    });

    test('ignores malformed overwrites', () {
      expect(
        DiscordMemberListId.overwritesOf({
          'permission_overwrites': [
            {'id': 'kept', 'allow': '1024', 'deny': 'not-a-number'},
            {'id': 42},
            {'allow': '1024'},
            'nonsense',
          ],
        }).map((overwrite) => overwrite.id),
        ['kept'],
      );
      expect(DiscordMemberListId.overwritesOf(const {}), isEmpty);
    });
  });

  group('viewport ranges', () {
    test('always subscribes the head page first', () {
      final ranges = DiscordMemberListRanges.forViewport(
        scrollOffset: 0,
        viewportHeight: 400,
        rowHeight: 40,
      );

      expect(ranges.first, [0, 99]);
      expect(ranges, [
        [0, 99],
      ]);
    });

    test('keeps the head page when scrolled far down', () {
      final ranges = DiscordMemberListRanges.forViewport(
        scrollOffset: 40 * 500,
        viewportHeight: 400,
        rowHeight: 40,
      );

      expect(ranges.first, [0, 99]);
      expect(ranges.length, greaterThan(1));
      for (final range in ranges) {
        expect(range[0] % DiscordMemberListRanges.pageSize, 0);
        expect(range[1] - range[0], DiscordMemberListRanges.pageSize - 1);
      }
      for (var index = 1; index < ranges.length; index++) {
        expect(ranges[index][0], greaterThan(ranges[index - 1][0]));
      }
    });

    test('covers the viewport plus half a viewport of overscan', () {
      final ranges = DiscordMemberListRanges.forViewport(
        scrollOffset: 40 * 250,
        viewportHeight: 400,
        rowHeight: 40,
      );

      // Rows 250..260 are visible and the half-viewport overscan reaches
      // 245..265, so the page holding them joins the mandatory head page.
      expect(ranges, [
        [0, 99],
        [200, 299],
      ]);
    });

    test('degrades to the head page for a degenerate viewport', () {
      expect(
        DiscordMemberListRanges.forViewport(
          scrollOffset: 100,
          viewportHeight: 0,
          rowHeight: 40,
        ),
        DiscordMemberListRanges.initial,
      );
      expect(
        DiscordMemberListRanges.forViewport(
          scrollOffset: 100,
          viewportHeight: 400,
          rowHeight: 0,
        ),
        DiscordMemberListRanges.initial,
      );
    });

    test('clamps a negative scroll offset', () {
      expect(
        DiscordMemberListRanges.forViewport(
          scrollOffset: -500,
          viewportHeight: 400,
          rowHeight: 40,
        ),
        [
          [0, 99],
        ],
      );
    });

    test('compares range sets structurally', () {
      const ranges = [
        [0, 99],
      ];
      expect(DiscordMemberListRanges.sameRanges(ranges, ranges), isTrue);
      expect(
        DiscordMemberListRanges.sameRanges(ranges, const [
          [0, 99],
        ]),
        isTrue,
      );
      expect(
        DiscordMemberListRanges.sameRanges(ranges, const [
          [0, 99],
          [100, 199],
        ]),
        isFalse,
      );
      expect(
        DiscordMemberListRanges.sameRanges(ranges, const [
          [0, 199],
        ]),
        isFalse,
      );
      expect(
        DiscordMemberListRanges.sameRanges(ranges, const [
          [0, 99, 0],
        ]),
        isFalse,
      );
    });
  });

  group('guild subscriptions', () {
    test('reports only real changes', () {
      final subscriptions = DiscordGuildSubscriptions();

      expect(subscriptions.setFlags('guild'), isTrue);
      expect(subscriptions.setFlags('guild'), isFalse);
      expect(
        subscriptions.setChannelRanges('guild', 'channel', const [
          [0, 99],
        ]),
        isTrue,
      );
      expect(
        subscriptions.setChannelRanges('guild', 'channel', const [
          [0, 99],
        ]),
        isFalse,
      );
      expect(
        subscriptions.setChannelRanges('guild', 'channel', const [
          [0, 99],
          [100, 199],
        ]),
        isTrue,
      );
    });

    test('evicts the least recently subscribed channel', () {
      final subscriptions = DiscordGuildSubscriptions();
      for (var index = 0; index < 6; index++) {
        subscriptions.setChannelRanges('guild', 'channel-$index', const [
          [0, 99],
        ]);
      }

      expect(subscriptions.rangesFor('guild', 'channel-0'), isNull);
      expect(subscriptions.rangesFor('guild', 'channel-5'), isNotNull);
      final channels =
          subscriptions.snapshot('guild')['channels']! as Map<String, Object?>;
      expect(channels.length, DiscordGuildSubscriptions.maxChannelsPerGuild);
    });

    test('an unchanged resubscribe protects a channel from eviction', () {
      final subscriptions = DiscordGuildSubscriptions();
      for (var index = 0; index < 5; index++) {
        subscriptions.setChannelRanges('guild', 'channel-$index', const [
          [0, 99],
        ]);
      }
      subscriptions.setChannelRanges('guild', 'channel-0', const [
        [0, 99],
      ]);
      subscriptions.setChannelRanges('guild', 'channel-5', const [
        [0, 99],
      ]);

      expect(subscriptions.rangesFor('guild', 'channel-0'), isNotNull);
      expect(subscriptions.rangesFor('guild', 'channel-1'), isNull);
    });

    test('builds the documented subscription object', () {
      final subscriptions = DiscordGuildSubscriptions()
        ..setFlags('guild', activities: false, memberUpdates: true)
        ..setChannelRanges('guild', 'channel', const [
          [0, 99],
        ]);

      expect(subscriptions.snapshot('guild'), {
        'typing': true,
        'threads': true,
        'activities': false,
        'member_updates': true,
        'members': <Object?>[],
        'channels': {
          'channel': [
            [0, 99],
          ],
        },
        'thread_member_lists': <Object?>[],
      });
      expect(subscriptions.snapshotAll().keys, ['guild']);
      expect(subscriptions.guildIds, ['guild']);
    });

    test('removes channels and guilds', () {
      final subscriptions = DiscordGuildSubscriptions()
        ..setChannelRanges('guild', 'channel', const [
          [0, 99],
        ]);

      expect(subscriptions.removeChannel('guild', 'missing'), isFalse);
      expect(subscriptions.removeChannel('guild', 'channel'), isTrue);
      subscriptions.removeGuild('guild');
      expect(subscriptions.guildIds, isEmpty);
      expect(subscriptions.snapshot('guild')['channels'], isEmpty);

      subscriptions
        ..setFlags('other')
        ..clear();
      expect(subscriptions.guildIds, isEmpty);
    });
  });

  group('member list store', () {
    Map<String, Object?> member(String id) => {
      'user': {'id': id, 'username': 'user-$id'},
      'roles': const <String>[],
      'presence': {'status': 'online'},
    };

    Map<String, Object?> dispatch({
      required List<Map<String, Object?>> ops,
      required List<Map<String, Object?>> groups,
      int memberCount = 0,
      int onlineCount = 0,
      String listId = 'everyone',
    }) => {
      'guild_id': 'guild',
      'id': listId,
      'ops': ops,
      'groups': groups,
      'member_count': memberCount,
      'online_count': onlineCount,
    };

    test('lays a SYNC out across the flat header and member row space', () {
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: [
            {
              'op': 'SYNC',
              'range': [0, 3],
              'items': [
                {
                  'group': {'id': 'online', 'count': 2},
                },
                {'member': member('a')},
                {'member': member('b')},
                {
                  'group': {'id': 'offline', 'count': 0},
                },
              ],
            },
          ],
          groups: [
            {'id': 'online', 'count': 2},
            {'id': 'offline', 'count': 0},
          ],
          memberCount: 3,
          onlineCount: 2,
        ),
      )!;

      final list = DiscordMemberListStore().apply(update);

      expect(list.rows, [
        const GuildMemberListGroupRow(groupId: 'online', count: 2),
        const GuildMemberListMemberRow('a'),
        const GuildMemberListMemberRow('b'),
        const GuildMemberListGroupRow(groupId: 'offline', count: 0),
      ]);
      expect(list.groups.map((group) => group.index), [0, 3]);
      expect(list.memberCount, 3);
      expect(list.onlineCount, 2);
      expect(list.version, 1);
      expect(list.isLoaded, isTrue);
      expect(list.everyoneMentionSize, 2);
      expect(list.hereMentionSize, 2);
      expect(list.key, 'guild:everyone');
      expect(
        update.memberItems.map((item) => item.member!['user']),
        hasLength(2),
      );
    });

    test('applies insert, replace and delete in order', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 2],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 2},
                  },
                  {'member': member('a')},
                  {'member': member('b')},
                ],
              },
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      final list = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INSERT',
                'index': 1,
                'item': {'member': member('c')},
              },
              {
                'op': 'UPDATE',
                'index': 2,
                'item': {'member': member('d')},
              },
              {'op': 'DELETE', 'index': 3},
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      expect(list.rows, [
        const GuildMemberListGroupRow(groupId: 'online', count: 2),
        const GuildMemberListMemberRow('c'),
        const GuildMemberListMemberRow('d'),
      ]);
      expect(list.version, 2);
    });

    test('invalidate stops at the first hole', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 1],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 4},
                  },
                  {'member': member('a')},
                ],
              },
              {
                'op': 'UPDATE',
                'index': 4,
                'item': {'member': member('e')},
              },
            ],
            groups: [
              {'id': 'online', 'count': 4},
            ],
          ),
        )!,
      );

      final list = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INVALIDATE',
                'range': [0, 4],
              },
            ],
            groups: [
              {'id': 'online', 'count': 4},
            ],
          ),
        )!,
      );

      expect(list.rows[0], isNull);
      expect(list.rows[1], isNull);
      expect(list.rows[2], isNull);
      expect(list.rows[4], const GuildMemberListMemberRow('e'));
    });

    test('groups resize the row space after the ops', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 2],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 2},
                  },
                  {'member': member('a')},
                  {'member': member('b')},
                ],
              },
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      final shrunk = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 1},
            ],
          ),
        )!,
      );
      expect(shrunk.rows, hasLength(2));

      final grown = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 3},
            ],
          ),
        )!,
      );
      expect(grown.rows, hasLength(4));
      expect(grown.rows.last, isNull);
    });

    test('tracks lists per guild and clears them', () {
      final store = DiscordMemberListStore();
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: const [],
          groups: [
            {'id': 'online', 'count': 0},
          ],
        ),
      )!;
      store.apply(update);

      expect(store.listFor('guild', 'everyone'), isNotNull);
      expect(store.lists, hasLength(1));
      store.clearGuild('other');
      expect(store.lists, hasLength(1));
      store.clearGuild('guild');
      expect(store.lists, isEmpty);

      store
        ..apply(update)
        ..clear();
      expect(store.lists, isEmpty);
    });

    test('ignores ops and payloads it cannot act on', () {
      final update = DiscordMemberListUpdate.fromDispatch({
        'guild_id': 'guild',
        'id': 'everyone',
        'ops': [
          {'op': 'CONTENT_INVENTORY'},
          {'op': 'SYNC', 'range': 'bad', 'items': <Object?>[]},
          {
            'op': 'SYNC',
            'range': [3, 1],
            'items': <Object?>[],
          },
          {
            'op': 'INVALIDATE',
            'range': [0],
          },
          {'op': 'INSERT', 'index': -1, 'item': <String, Object?>{}},
          {'op': 'UPDATE', 'index': 0, 'item': <String, Object?>{}},
          {'op': 'DELETE', 'index': 'x'},
          {'op': 42},
          {
            'op': 'SYNC',
            'range': [0, 1],
            'items': [
              {
                'member': {'user': 'not-an-object'},
              },
              {
                'group': {'count': 1},
              },
            ],
          },
        ],
        'groups': [
          {'count': 1},
          {'id': 'online', 'count': -5},
        ],
        'member_count': 'bad',
        'online_count': null,
      })!;

      final list = DiscordMemberListStore().apply(update);

      expect(update.ops, hasLength(1));
      expect(list.memberCount, 0);
      expect(list.onlineCount, 0);
      expect(list.groups.single.count, 0);
      expect(list.rows, hasLength(1));
      expect(update.memberItems, isEmpty);
    });

    test('rejects a dispatch without identifiers', () {
      expect(DiscordMemberListUpdate.fromDispatch(const {}), isNull);
      expect(
        DiscordMemberListUpdate.fromDispatch(const {'guild_id': 'guild'}),
        isNull,
      );
    });

    test('an out of range insert grows the row space', () {
      final list = DiscordMemberListStore().apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INSERT',
                'index': 3,
                'item': {'member': member('a')},
              },
            ],
            groups: const [],
          ),
        )!,
      );

      expect(list.rows, hasLength(4));
      expect(list.rows.last, const GuildMemberListMemberRow('a'));
      expect(list.rows.first, isNull);
    });

    test('a pending list reports that it has not loaded', () {
      final pending = GuildMemberList.pending(
        guildId: 'guild',
        listId: 'everyone',
      );

      expect(pending.isLoaded, isFalse);
      expect(pending.rows, isEmpty);
      expect(pending.toString(), contains('guild:everyone'));
      expect(
        const GuildMemberListGroupRow(groupId: 'online', count: 1).toString(),
        contains('online'),
      );
      expect(
        const GuildMemberListMemberRow('a').hashCode,
        const GuildMemberListMemberRow('a').hashCode,
      );
      expect(
        const GuildMemberListGroup(id: 'online', count: 1, index: 0),
        const GuildMemberListGroup(id: 'online', count: 1, index: 0),
      );
      expect(
        const GuildMemberListGroup(id: 'online', count: 1, index: 0).hashCode,
        const GuildMemberListGroup(id: 'online', count: 1, index: 0).hashCode,
      );
    });

    test('carries members out of insert and replace ops', () {
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: [
            {
              'op': 'INSERT',
              'index': 0,
              'item': {'member': member('a')},
            },
            {
              'op': 'UPDATE',
              'index': 0,
              'item': {'member': member('b')},
            },
            {
              'op': 'INSERT',
              'index': 1,
              'item': {
                'group': {'id': 'online', 'count': 1},
              },
            },
            {
              'op': 'INVALIDATE',
              'range': [0, 1],
            },
            {'op': 'DELETE', 'index': 1},
          ],
          groups: const [],
        ),
      )!;

      expect(
        update.memberItems.map(
          (item) => (item.row as GuildMemberListMemberRow).userId,
        ),
        ['a', 'b'],
      );
      expect(update.memberItems.first.presence, {'status': 'online'});
    });

    test('reuses a list when nothing is overridden', () {
      final list = GuildMemberList.pending(guildId: 'guild', listId: 'list');

      final copy = list.copyWith();

      expect(copy.rows, list.rows);
      expect(copy.groups, list.groups);
      expect(copy.memberCount, list.memberCount);
      expect(copy.onlineCount, list.onlineCount);
      expect(copy.version, list.version);
    });

    test('rows and overwrite bits expose value semantics', () {
      const group = GuildMemberListGroupRow(groupId: 'online', count: 2);

      expect(group.hashCode, group.hashCode);
      expect(
        group,
        isNot(const GuildMemberListGroupRow(groupId: 'x', count: 2)),
      );
      expect(const GuildMemberListMemberRow('a').toString(), contains('a'));
      expect(const GuildMemberListMemberRow('a'), isNot(group));

      final overwrite = DiscordPermissionOverwrite.fromJson(const {
        'id': 'role',
      })!;
      expect(overwrite.allow, BigInt.zero);
      expect(overwrite.deny, BigInt.zero);
      expect(overwrite.grants(DiscordMemberListId.viewChannel), isFalse);
    });

    test('offline members are excluded from the here mention size', () {
      final list = DiscordMemberListStore().apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 3},
              {'id': 'offline', 'count': 7},
            ],
          ),
        )!,
      );

      expect(list.everyoneMentionSize, 10);
      expect(list.hereMentionSize, 3);
    });
  });
}
