import 'package:flucord/src/data/discord/discord_guild_subscriptions.dart';
import 'package:flucord/src/data/discord/discord_member_list_id.dart';
import 'package:flucord/src/data/discord/discord_member_list_ranges.dart';
import 'package:flucord/src/data/discord/discord_member_list_store.dart';
import 'package:flucord/src/data/discord/discord_member_list_update.dart';
import 'package:flucord/src/data/discord/discord_murmur3.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flutter_test/flutter_test.dart';

part 'discord_member_list_store_cases.dart';

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

  _memberListStoreCases();
  _allocationGuard();
}

void _allocationGuard() {
  test('a hostile row index cannot force an unbounded allocation', () {
    // index is server-supplied, so it is attacker-influenced input. Growing the
    // row space to reach it is correct for real pages and catastrophic here.
    final update = DiscordMemberListUpdate.fromDispatch({
      'guild_id': 'guild',
      'id': 'everyone',
      'ops': [
        {
          'op': 'UPDATE',
          'index': 2000000000,
          'item': {
            'member': {
              'user': {'id': 'a'},
            },
          },
        },
      ],
      'groups': const <Object?>[],
      'member_count': 0,
      'online_count': 0,
    })!;

    final list = DiscordMemberListStore().apply(update);

    expect(list.rows.length, lessThanOrEqualTo(DiscordMemberListStore.maxRows));
  });
}
