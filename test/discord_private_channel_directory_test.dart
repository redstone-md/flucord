import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_bootstrap.dart';
import 'package:flucord/src/data/discord/discord_private_channel_directory.dart';
import 'package:flucord/src/data/discord/discord_private_channel_order.dart';
import 'package:flucord/src/data/discord/discord_snowflake.dart';

void main() {
  group('ordering', () {
    test('keys a channel on its own id when nothing was ever sent', () {
      expect(
        DiscordPrivateChannelOrder.effectiveLastMessageId(const {
          'id': '111111111111111111',
        }),
        '111111111111111111',
      );
      expect(
        DiscordPrivateChannelOrder.effectiveLastMessageId(const {
          'id': '111111111111111111',
          'last_message_id': null,
        }),
        '111111111111111111',
      );
      expect(DiscordPrivateChannelOrder.effectiveLastMessageId(const {}), '');
    });

    test('prefers the read-state cursor over the channel record', () {
      expect(
        DiscordPrivateChannelOrder.effectiveLastMessageId(
          const {
            'id': '111111111111111111',
            'last_message_id': '234567890123456789',
          },
          readStateLastMessageIds: const {
            '111111111111111111': '987654321098765432',
          },
        ),
        '987654321098765432',
      );
    });

    test('promotes a message-request timestamp when it is the newer one', () {
      final requestedAt = DateTime.utc(2026, 7, 20, 12);
      final promoted = DiscordPrivateChannelOrder.effectiveLastMessageId({
        'id': '111111111111111111',
        'last_message_id': '234567890123456789',
        'is_message_request_timestamp': requestedAt.toIso8601String(),
      });

      expect(
        DiscordSnowflake.timestampMillis(promoted),
        requestedAt.millisecondsSinceEpoch,
      );
      // An older request never displaces a real message.
      expect(
        DiscordPrivateChannelOrder.effectiveLastMessageId(const {
          'id': '111111111111111111',
          'last_message_id': '987654321098765432',
          'is_message_request_timestamp': '2016-01-01T00:00:00Z',
        }),
        '987654321098765432',
      );
      expect(
        DiscordPrivateChannelOrder.effectiveLastMessageId(const {
          'id': '111111111111111111',
          'is_message_request_timestamp': 'not a timestamp',
        }),
        '111111111111111111',
      );
    });

    test('sorts by descending activity and breaks ties on the channel id', () {
      final sorted = DiscordPrivateChannelOrder.sorted(const [
        {'id': '222222222222222222', 'last_message_id': '234567890123456789'},
        {'id': '333333333333333333'},
        {'id': '111111111111111111', 'last_message_id': '987654321098765432'},
      ]);

      expect(sorted.map((channel) => channel['id']), [
        '111111111111111111',
        '333333333333333333',
        '222222222222222222',
      ]);

      // Channels with no snowflake at all still come out in a stable order.
      final opaque = DiscordPrivateChannelOrder.sorted(const [
        {'id': 'dm-a'},
        {'id': 'dm-c'},
        {'id': 'dm-b'},
      ]);
      expect(opaque.map((channel) => channel['id']), ['dm-c', 'dm-b', 'dm-a']);
    });
  });

  group('directory', () {
    test('replaces its contents with the READY list', () {
      final directory = DiscordPrivateChannelDirectory()
        ..applyReady(const [
          {'id': '111111111111111111', 'type': 1},
          {'id': 222, 'type': 1},
          {'id': '', 'type': 1},
        ]);

      expect(directory.ordered.single['id'], '111111111111111111');

      directory.applyReady(const [
        {'id': '222222222222222222', 'type': 1},
      ]);
      expect(directory.ordered.single['id'], '222222222222222222');
    });

    test('rebuilds from READY before applying the lazy top-up', () {
      final directory = DiscordPrivateChannelDirectory()
        ..applyReady(const [
          {'id': '111111111111111111', 'type': 1, 'name': 'from ready'},
          {'id': '222222222222222222', 'type': 1},
        ]);

      // A second supplemental must not compound: each one starts again from the
      // remembered READY list, so the first top-up's edits do not survive it.
      directory.applySupplemental(const [
        {'id': '111111111111111111', 'type': 1, 'name': 'from lazy'},
        {'id': '333333333333333333', 'type': 3},
      ]);
      directory.applySupplemental(const [
        {'id': '333333333333333333', 'type': 3, 'name': 'group'},
      ]);

      final byId = {
        for (final channel in directory.ordered) channel['id']: channel,
      };
      expect(byId.keys, hasLength(3));
      expect(byId['111111111111111111']!['name'], 'from ready');
      expect(byId['333333333333333333']!['name'], 'group');
    });

    test('accepts a lazy top-up that arrives without a READY list', () {
      final directory = DiscordPrivateChannelDirectory()
        ..applySupplemental(const [
          {'id': '111111111111111111', 'type': 1},
        ]);

      expect(directory.ordered.single['id'], '111111111111111111');

      directory.clear();
      expect(directory.ordered, isEmpty);
    });
  });

  group('bootstrap', () {
    test('expands READY recipients and orders the DM directory', () {
      final bootstrap = DiscordDesktopBootstrap()
        ..acceptReady(const {
          'user': {'id': 'me', 'username': 'member'},
          'users': [
            {'id': '123456789012345678', 'username': 'jack'},
            {'id': '234567890123456789', 'username': 'jill'},
          ],
          'private_channels': [
            {
              'id': '222222222222222222',
              'type': 1,
              'recipient_ids': ['234567890123456789'],
            },
            {
              'id': '111111111111111111',
              'type': 1,
              'recipient_ids': ['123456789012345678'],
              'last_message_id': '987654321098765432',
            },
          ],
          'guilds': [
            {
              'id': '333333333333333333',
              'channels': [
                {'id': '987654321098765432', 'type': 0},
              ],
            },
          ],
        });

      final snapshot = bootstrap.snapshot()!;
      expect(snapshot.currentUser['id'], 'me');
      expect(snapshot.guilds.single['id'], '333333333333333333');
      expect(snapshot.channelsByGuild['333333333333333333'], hasLength(1));
      expect(snapshot.directChannels.map((channel) => channel['id']), [
        '111111111111111111',
        '222222222222222222',
      ]);
      final recipients = snapshot.directChannels.first['recipients']! as List;
      expect((recipients.single as Map)['username'], 'jack');
      expect(snapshot.directChannels.first['recipient_ids'], isNull);
    });

    test('joins lazy private channels and then drops the user table', () {
      final bootstrap = DiscordDesktopBootstrap()
        ..acceptReady(const {
          'user': {'id': 'me'},
          'users': [
            {'id': '123456789012345678', 'username': 'jack'},
          ],
          'private_channels': [
            {
              'id': '111111111111111111',
              'type': 1,
              'recipient_ids': ['123456789012345678'],
            },
          ],
        })
        ..acceptSupplemental(const {
          'lazy_private_channels': [
            {
              'id': '222222222222222222',
              'type': 1,
              'recipient_ids': ['123456789012345678'],
              'last_message_id': '987654321098765432',
            },
          ],
        });

      expect(bootstrap.users.user('123456789012345678'), isNull);
      expect(bootstrap.snapshot()!.directChannels.map((c) => c['id']), [
        '222222222222222222',
        '111111111111111111',
      ]);
    });

    test('keeps a channel whose recipient the user table never carried', () {
      final bootstrap = DiscordDesktopBootstrap()
        ..acceptReady(const {
          'user': {'id': 'me'},
          'private_channels': [
            {
              'id': '111111111111111111',
              'type': 1,
              'recipient_ids': ['123456789012345678'],
            },
          ],
        });

      expect(bootstrap.users.unresolvedIds, {'123456789012345678'});
      expect(
        bootstrap.snapshot()!.directChannels.single['recipients'],
        isEmpty,
      );
    });

    test('has no snapshot before READY and forgets everything on reset', () {
      final bootstrap = DiscordDesktopBootstrap();
      expect(bootstrap.snapshot(), isNull);

      // READY always arrives before any GUILD_CREATE, so the accumulation is
      // driven in that order rather than the reverse.
      bootstrap
        ..acceptReady(const {
          'user': {'id': 'me'},
        })
        ..acceptGuild(const {'id': 'guild-without-channels'})
        ..acceptGuild(const {'name': 'guild without an id'})
        ..acceptSupplemental(const {});
      expect(bootstrap.snapshot()!.guilds, hasLength(1));

      // A reconnect replays READY, and that replay is authoritative: a guild
      // the account left while disconnected must not survive it.
      bootstrap.acceptReady(const {
        'user': {'id': 'me'},
      });
      expect(bootstrap.snapshot()!.guilds, isEmpty);

      bootstrap.reset();
      expect(bootstrap.snapshot(), isNull);
    });
  });
}
