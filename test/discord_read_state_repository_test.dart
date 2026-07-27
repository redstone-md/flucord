import 'package:flucord/src/data/discord/discord_desktop_rest_protocol.dart';
import 'package:flucord/src/data/discord/discord_read_state_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _threadId = '333333333333333333';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';
const _newestMessage = '987654321098765432';

void main() {
  test('hydrates from READY and republishes on every dispatch', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);
    final seen = <ReadStateSnapshot>[];
    repository.updates.listen(seen.add);

    repository.acceptGatewayDispatch('READY', {
      'read_state': {
        'version': 5,
        'partial': false,
        'entries': [
          {
            'id': _channelId,
            'last_message_id': _olderMessage,
            'mention_count': 2,
          },
        ],
      },
      'user_guild_settings': {
        'version': 3,
        'partial': false,
        'entries': [
          {'guild_id': _guildId, 'muted': true},
        ],
      },
    });
    repository.acceptGatewayDispatch('MESSAGE_CREATE', const {});
    await _settle();

    expect(seen, hasLength(1));
    expect(repository.current.forChannel(_channelId)!.mentionCount, 2);
    expect(repository.current.settingsFor(_guildId).muted, isTrue);
  });

  test(
    'acknowledges optimistically, then sends once the debounce lapses',
    () async {
      final transport = _FakeTransport(responses: {'token': 'rolling'});
      final repository = _repository(transport);
      addTearDown(repository.close);
      repository.acceptGatewayDispatch(
        'READY',
        _readyWithCursor(_olderMessage),
      );

      await repository.acknowledge(_channel(), messageId: _newestMessage);

      expect(
        repository.current.forChannel(_channelId)!.lastAckedId,
        _newestMessage,
      );
      expect(repository.current.forChannel(_channelId)!.mentionCount, 0);
      expect(transport.requests, isEmpty);

      await _settle(const Duration(milliseconds: 60));
      expect(transport.requests, hasLength(1));
      final body = transport.requests.single.body!;
      expect(body['token'], isNull);
      expect(body['last_viewed'], isA<int>());
      // The read state came from READY with no flags, and this is a guild
      // channel, so the recomputed value differs and travels.
      expect(body['flags'], ReadStateFlags.guildChannel);
      expect(repository.ackToken, 'rolling');
    },
  );

  test('sends at once when the channel already has mentions', () async {
    final transport = _FakeTransport();
    final repository = _repository(
      transport,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', {
      'read_state': {
        'entries': [
          {
            'id': _channelId,
            'last_message_id': _olderMessage,
            'mention_count': 4,
            'flags': ReadStateFlags.guildChannel,
          },
        ],
      },
    });

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await _settle();

    expect(transport.requests, hasLength(1));
    // The stored flags already say "guild channel", so the key is omitted.
    expect(transport.requests.single.body!.containsKey('flags'), isFalse);
  });

  test('skips an acknowledgement that would move nothing', () async {
    final transport = _FakeTransport();
    var now = DateTime.utc(2026, 7, 26, 12);
    final repository = DiscordReadStateRepository(
      transport,
      delay: _noDelay,
      ackDebounce: Duration.zero,
      clock: () => now,
    );
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', _readyWithCursor(_olderMessage));

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await _settle();
    expect(transport.requests, hasLength(1));

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await _settle();
    expect(transport.requests, hasLength(1));

    // R04's only reason to re-ack a read channel: the day counter moved.
    now = now.add(const Duration(days: 1));
    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await _settle();
    expect(transport.requests, hasLength(2));
  });

  test('marks unread with the manual body and cancels a pending ack', () async {
    final transport = _FakeTransport();
    final repository = _repository(
      transport,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', _readyWithCursor(_olderMessage));

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await repository.markUnread(
      _channel(),
      messageId: _olderMessage,
      mentionCount: -2,
    );
    await _settle();

    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.body, {
      'manual': true,
      'mention_count': 0,
    });
    expect(
      repository.current.forChannel(_channelId)!.lastAckedId,
      _olderMessage,
    );
  });

  test('a remote manual ack cancels our pending acknowledgement', () async {
    final transport = _FakeTransport();
    final repository = _repository(
      transport,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', _readyWithCursor(_olderMessage));

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    repository.acceptGatewayDispatch('MESSAGE_ACK', const {
      'channel_id': _channelId,
      'message_id': _olderMessage,
      'manual': true,
      'mention_count': 1,
    });
    await _settle(const Duration(milliseconds: 60));

    expect(transport.requests, isEmpty);
    expect(
      repository.current.forChannel(_channelId)!.lastAckedId,
      _olderMessage,
    );
  });

  test('marks a guild read in bulk plus its two feature acks', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', _readyWithCursor(_olderMessage));

    await repository.markSpaceRead(_guildId, [
      _channel(lastMessageId: _newestMessage),
      _channel(id: _threadId, lastMessageId: _newerMessage, isThread: true),
      // No pointer at all, and a channel that belongs elsewhere: neither can
      // produce an entry.
      _channel(id: _threadId),
      _channel(id: _threadId, spaceId: CommunitySpace.directMessagesId),
    ]);
    await repository.flush();

    final bulk = transport.requests
        .where((request) => request.path == '/read-states/ack-bulk')
        .single;
    expect((bulk.body!['read_states']! as List), hasLength(2));
    expect(
      transport.requests.map((request) => request.path),
      containsAll([
        '/guilds/$_guildId/ack/1/$_guildId',
        '/guilds/$_guildId/ack/4/$_guildId',
      ]),
    );
    expect(
      repository.current.forChannel(_channelId)!.lastAckedId,
      _newestMessage,
    );
    expect(
      repository.current
          .forEntity(ReadStateType.guildEvent, _guildId)!
          .lastAckedId,
      _guildId,
    );
  });

  test('marking direct messages read raises no guild feature ack', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.markSpaceRead(CommunitySpace.directMessagesId, [
      _channel(
        spaceId: CommunitySpace.directMessagesId,
        lastMessageId: _newestMessage,
      ),
    ]);
    await repository.flush();

    expect(transport.requests.map((request) => request.path), [
      '/read-states/ack-bulk',
    ]);
  });

  test('skips channels that are already read and have no mentions', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);
    repository.acceptGatewayDispatch('READY', _readyWithCursor(_newestMessage));

    await repository.markSpaceRead(CommunitySpace.directMessagesId, [
      _channel(
        spaceId: CommunitySpace.directMessagesId,
        lastMessageId: _newestMessage,
      ),
    ]);
    await repository.flush();

    expect(transport.requests, isEmpty);
  });

  test('routes a guild settings patch through the bulk route', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.updateSpaceNotificationSettings(
      _guildId,
      const GuildNotificationSettingsPatch(muted: true, mobilePush: false),
    );

    expect(transport.requests.single.path, '/users/@me/guilds/settings');
    expect(transport.requests.single.body, {
      'guilds': {
        _guildId: {'muted': true, 'mobile_push': false},
      },
    });
    expect(repository.current.settingsFor(_guildId).muted, isTrue);
    expect(repository.current.settingsFor(_guildId).mobilePush, isFalse);
  });

  test('routes a DM settings patch through the single-guild route', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.updateSpaceNotificationSettings(
      CommunitySpace.directMessagesId,
      const GuildNotificationSettingsPatch(suppressEveryone: true),
    );

    expect(transport.requests.single.path, '/users/@me/guilds/@me/settings');
    expect(transport.requests.single.body, {'suppress_everyone': true});
  });

  test('wraps a channel override into the settings body', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.updateChannelNotificationOverride(
      spaceId: _guildId,
      channelId: _channelId,
      patch: const ChannelNotificationOverridePatch(muted: true),
    );

    expect(transport.requests.single.body, {
      'guilds': {
        _guildId: {
          'channel_overrides': {
            _channelId: {'muted': true},
          },
        },
      },
    });
    expect(
      repository.current.settingsFor(_guildId).overrideFor(_channelId)!.muted,
      isTrue,
    );

    // A second edit merges into the override rather than replacing it.
    await repository.updateChannelNotificationOverride(
      spaceId: _guildId,
      channelId: _channelId,
      patch: const ChannelNotificationOverridePatch(
        messageNotifications: MessageNotificationLevel.onlyMentions,
      ),
    );
    final override = repository.current
        .settingsFor(_guildId)
        .overrideFor(_channelId)!;
    expect(override.muted, isTrue);
    expect(
      override.messageNotifications,
      MessageNotificationLevel.onlyMentions,
    );
  });

  test('an empty patch sends nothing', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.updateSpaceNotificationSettings(
      _guildId,
      const GuildNotificationSettingsPatch(),
    );
    await repository.updateChannelNotificationOverride(
      spaceId: _guildId,
      channelId: _channelId,
      patch: const ChannelNotificationOverridePatch(),
    );

    expect(transport.requests, isEmpty);
  });

  test('client_state collapses until a version has been seen', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    expect(repository.identifyClientState(), {
      'guild_versions': <String, Object?>{},
    });

    repository.acceptGatewayDispatch('READY', {
      'read_state': {'version': 5, 'partial': false, 'entries': []},
      'user_guild_settings': {'version': 0, 'partial': false, 'entries': []},
    });

    expect(repository.identifyClientState(), {
      'guild_versions': <String, Object?>{},
      'read_state_version': 5,
    });

    repository.acceptGatewayDispatch('USER_GUILD_SETTINGS_UPDATE', const {
      'guild_id': _guildId,
      'version': 9,
    });
    expect(repository.identifyClientState()['user_guild_settings_version'], 9);
  });

  test('computes the two identify snowflake cursors', () async {
    final transport = _FakeTransport();
    final repository = _repository(transport);
    addTearDown(repository.close);

    repository.acceptGatewayDispatch('READY', {
      'read_state': {
        'partial': false,
        'entries': [
          {'id': _channelId, 'last_message_id': _newestMessage},
          {'id': _threadId, 'last_message_id': _newerMessage},
        ],
      },
    });

    expect(repository.highestLastMessageId, _newestMessage);
    expect(repository.privateChannelsVersion, '0');
    repository.setPrivateChannelIds(const [_threadId]);
    expect(repository.privateChannelsVersion, _newerMessage);
  });

  test('rebinding the account resets the ack token', () async {
    final transport = _FakeTransport(responses: {'token': 'rolling'});
    final repository = _repository(transport);
    addTearDown(repository.close);

    await repository.acknowledge(_channel(), messageId: _newestMessage);
    await _settle();
    expect(repository.ackToken, 'rolling');

    repository.setCurrentUserId(_guildId);
    expect(repository.ackToken, isNull);
  });
}

DiscordReadStateRepository _repository(
  _FakeTransport transport, {
  Duration debounce = Duration.zero,
}) => DiscordReadStateRepository(
  transport,
  delay: _noDelay,
  ackDebounce: debounce,
);

Future<void> _noDelay(Duration duration) async {}

Future<void> _settle([Duration duration = const Duration(milliseconds: 20)]) =>
    Future<void>.delayed(duration);

Map<String, Object?> _readyWithCursor(String cursor) => {
  'read_state': {
    'version': 1,
    'partial': false,
    'entries': [
      {'id': _channelId, 'last_message_id': cursor},
    ],
  },
};

ConversationChannel _channel({
  String id = _channelId,
  String spaceId = _guildId,
  String? lastMessageId,
  bool isThread = false,
}) => ConversationChannel(
  id: id,
  spaceId: spaceId,
  name: 'general',
  topic: '',
  kind: ChannelKind.text,
  isThread: isThread,
  lastMessageId: lastMessageId,
);

final class _FakeTransport implements DiscordReadStateTransport {
  _FakeTransport({this.responses});

  final Map<String, Object?>? responses;
  final List<DiscordDesktopRestRequest> requests = [];

  @override
  Future<Map<String, Object?>?> sendReadStateRequest(
    DiscordDesktopRestRequest request,
  ) async {
    requests.add(request);
    return responses;
  }
}
