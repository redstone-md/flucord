/// A big account and its traffic, as the raw payloads Discord would send.
///
/// Everything here is made up and repeats exactly from one run to the next. The
/// sizes are the ones the domain benchmark uses (`tool/bench/domain_bench.dart`).
/// They are a stress load, not a picture of a real account.
library;

import 'dart:math';

import '../../test/support/fake_discord_wire.dart';
import '../../test/support/session_harness.dart';

const _guildCount = 100;
const _channelsPerGuild = 50;
const _memberCount = 20000;
const _membersPerGuild = _memberCount ~/ _guildCount;

/// Every channel names this as its newest message, and the read state names it
/// as read, so the account starts with nothing unread. Each message the history
/// routes serve is older, and each new one from [SyntheticTraffic] is newer.
final _lastReadMessage = int.parse(_snowflake(89, 0));

const _words = [
  'forge',
  'anvil',
  'ember',
  'hammer',
  'quench',
  'temper',
  'bellows',
  'slag',
  'ingot',
  'rivet',
  'tongs',
  'crucible',
  'alloy',
  'chisel',
  'file',
  'steel',
];

/// An 18 digit id, spelled in parts. The repo's privacy audit refuses a whole id
/// in the source unless it is on its short list of known fake ones.
String _snowflake(int kind, int index) => '$kind${'$index'.padLeft(16, '0')}';

String _memberId(int index) => _snowflake(11, index);

/// The first guild has the id of the harness's guild.
String _guildId(int index) => _snowflake(20, index + 1);

/// The harness's two channels come first in the harness's guild, so a scenario
/// can open them by the harness's names.
List<String> _channelIdsOf(int guild) => [
  if (guild == 0) ...[SessionHarness.channelId, SessionHarness.otherChannelId],
  for (var channel = guild == 0 ? 2 : 0; channel < _channelsPerGuild; channel++)
    _snowflake(31, guild * _channelsPerGuild + channel),
];

Iterable<int> _membersOf(int guild) => Iterable.generate(
  _membersPerGuild,
  (index) => guild * _membersPerGuild + index,
);

/// The READY of the big account: 5000 channels and 20000 members over 100
/// guilds, built on the harness's default READY. [activeChannelName] names the
/// harness's main channel, so a later READY can make a change the screen shows.
Map<String, Object?> largeReady({String activeChannelName = 'general'}) {
  final ready = SessionHarness.defaultReady();
  final harnessGuild =
      (ready['guilds']! as List).single as Map<String, Object?>;
  final everyoneRole = (harnessGuild['roles']! as List).single as Map;
  final guilds = [for (var guild = 0; guild < _guildCount; guild++) guild];
  final lastRead = '$_lastReadMessage';
  return ready
    ..['users'] = [
      ...ready['users']! as List,
      for (var member = 0; member < _memberCount; member++)
        {'id': _memberId(member), 'username': 'member$member'},
    ]
    ..['guilds'] = [
      for (final guild in guilds)
        rawGuild(
          id: _guildId(guild),
          name: guild == 0 ? 'The Forge' : 'Guild $guild',
          everyonePermissions: everyoneRole['permissions'] as String,
          channels: [
            for (final id in _channelIdsOf(guild))
              rawChannel(
                id: id,
                // The sidebar sorts these by name, and it builds only the rows
                // on screen, so the harness's two channels must sort first.
                name: switch (id) {
                  SessionHarness.channelId => activeChannelName,
                  SessionHarness.otherChannelId => 'random',
                  _ => 'room-$id',
                },
                lastMessageId: lastRead,
              ),
          ],
        ),
    ]
    ..['merged_members'] = [
      for (final guild in guilds)
        [
          for (final member in _membersOf(guild))
            {'user_id': _memberId(member), 'roles': <Object?>[]},
        ],
    ]
    ..['read_state'] = {
      'version': 1,
      'partial': false,
      'entries': [
        for (final guild in guilds)
          for (final id in _channelIdsOf(guild))
            {'id': id, 'last_message_id': lastRead, 'mention_count': 0},
      ],
    };
}

/// The READY_SUPPLEMENTAL that follows [largeReady], with each member online.
Map<String, Object?> largeSupplemental() {
  final guilds = [for (var guild = 0; guild < _guildCount; guild++) guild];
  return {
    'guilds': [
      for (final guild in guilds) {'id': _guildId(guild)},
    ],
    'lazy_private_channels': <Object?>[],
    'merged_presences': {
      'friends': <Object?>[],
      'guilds': [
        for (final guild in guilds)
          [
            for (final member in _membersOf(guild))
              {
                'user_id': _memberId(member),
                'status': 'online',
                'client_status': {'desktop': 'online'},
                'activities': <Object?>[],
              },
          ],
      ],
    },
  };
}

/// A member of the harness's guild, whose status the member list shows.
String get visibleMemberId => _memberId(0);

/// New gateway events, and the history pages of a channel, from one seed.
final class SyntheticTraffic {
  SyntheticTraffic({int seed = 31}) : _random = Random(seed);

  final Random _random;
  late int _nextMessage = _lastReadMessage + 1;
  late int _nextHistoryMessage = _lastReadMessage;

  /// A message for [channelId] in the harness's guild. Its id is newer than any
  /// message before it.
  Map<String, Object?> message(String channelId) =>
      _messageWithId('${_nextMessage++}', channelId);

  /// A status change of a random member of a random guild.
  Map<String, Object?> presence() {
    final member = _random.nextInt(_memberCount);
    return presenceOf(
      _memberId(member),
      guildId: _guildId(member ~/ _membersPerGuild),
      status: const ['online', 'idle', 'dnd', 'offline'][_random.nextInt(4)],
    );
  }

  /// What `PRESENCE_UPDATE` carries when this member gets this status.
  Map<String, Object?> presenceOf(
    String memberId, {
    required String guildId,
    required String status,
  }) => {
    'user': {'id': memberId},
    'guild_id': guildId,
    'status': status,
    'client_status': {'desktop': status},
    'activities': <Object?>[],
  };

  /// Makes the history of [channelId] hold [count] messages, served in pages the
  /// way Discord does: newest first, and older than `before` when it is given.
  /// Returns the id of the oldest message and of the newest.
  (String, String) routeHistory(
    FakeDiscordTransport transport,
    String channelId, {
    required int count,
  }) {
    // Each channel gets ids of its own: a message id is unique across Discord.
    final newestId = _nextHistoryMessage;
    final oldestId = newestId - count + 1;
    _nextHistoryMessage = oldestId - 1;
    final newestFirst = [
      for (var id = newestId; id >= oldestId; id--)
        _messageWithId('$id', channelId, minutesAgo: newestId - id),
    ];
    transport.on('GET', '/api/v9/channels/$channelId/messages', (request) {
      final query = request.uri.queryParameters;
      final before = int.tryParse(query['before'] ?? '');
      return jsonResponse(
        newestFirst
            .where(
              (m) => before == null || int.parse(m['id']! as String) < before,
            )
            .take(int.parse(query['limit'] ?? '100'))
            .toList(),
      );
    });
    return ('$oldestId', '$newestId');
  }

  Map<String, Object?> _messageWithId(
    String id,
    String channelId, {
    int minutesAgo = 0,
  }) => rawMessage(
    id: id,
    channelId: channelId,
    guildId: SessionHarness.guildId,
    authorId: _memberId(_random.nextInt(_membersPerGuild)),
    content: _sentence(),
    timestamp: DateTime.utc(
      2026,
      7,
      25,
    ).subtract(Duration(minutes: minutesAgo * 7)).toIso8601String(),
  );

  /// Between 3 and 40 words. One in four has markdown, so the timeline parses
  /// some rows and shows the rest as plain text, as it does in a real channel.
  String _sentence() {
    final words = [
      for (var word = 3 + _random.nextInt(38); word > 0; word--)
        _words[_random.nextInt(_words.length)],
    ];
    if (_random.nextInt(4) == 0) words[0] = '**${words[0]}**';
    return words.join(' ');
  }
}
