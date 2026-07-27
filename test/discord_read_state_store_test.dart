import 'package:flucord/src/data/discord/discord_read_state_store.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _otherChannelId = '333333333333333333';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';
const _newestMessage = '987654321098765432';

void main() {
  test('hydrates read state, settings and account flags from READY', () {
    final store = DiscordReadStateStore();

    expect(store.accept('READY', _ready()), isTrue);

    final snapshot = store.snapshot;
    expect(snapshot.readStateVersion, 42);
    expect(snapshot.userGuildSettingsVersion, 7);
    expect(
      snapshot.accountNotificationFlags,
      AccountNotificationFlags.useNewNotifications,
    );
    expect(snapshot.forChannel(_channelId)!.lastAckedId, _olderMessage);
    expect(snapshot.forChannel(_channelId)!.mentionCount, 2);
    expect(
      snapshot.forEntity(ReadStateType.guildEvent, _guildId)!.lastAckedId,
      _newerMessage,
    );
    expect(snapshot.settingsFor(_guildId).muted, isTrue);
    expect(
      snapshot.settingsFor(CommunitySpace.directMessagesId).suppressEveryone,
      isTrue,
    );
  });

  test('a full READY replaces, a partial one merges', () {
    final store = DiscordReadStateStore()..accept('READY', _ready());

    store.accept('READY', {
      'read_state': {
        'version': 43,
        'partial': true,
        'entries': [
          {'id': _otherChannelId, 'last_message_id': _newestMessage},
        ],
      },
      'user_guild_settings': {
        'version': 8,
        'partial': true,
        'entries': [
          {'guild_id': _guildId, 'muted': false},
        ],
      },
    });

    var snapshot = store.snapshot;
    expect(snapshot.forChannel(_channelId), isNotNull);
    expect(snapshot.forChannel(_otherChannelId), isNotNull);
    expect(snapshot.settingsFor(_guildId).muted, isFalse);
    expect(
      snapshot.settingsFor(CommunitySpace.directMessagesId).suppressEveryone,
      isTrue,
    );
    expect(snapshot.readStateVersion, 43);
    expect(snapshot.userGuildSettingsVersion, 8);

    store.accept('READY', {
      'read_state': {
        'version': 44,
        'partial': false,
        'entries': [
          {'id': _otherChannelId, 'last_message_id': _newestMessage},
        ],
      },
      'user_guild_settings': {'version': 9, 'partial': false, 'entries': []},
    });

    snapshot = store.snapshot;
    expect(snapshot.forChannel(_channelId), isNull);
    expect(snapshot.forChannel(_otherChannelId), isNotNull);
    expect(snapshot.settings, isEmpty);
  });

  test('reads a version the wire sent as a float', () {
    final store = DiscordReadStateStore();
    store.accept('READY', const {
      'read_state': {'version': 12.0, 'partial': false, 'entries': []},
    });
    expect(store.snapshot.readStateVersion, 12);
  });

  test('a READY with no read-state block still announces itself', () {
    final store = DiscordReadStateStore();
    expect(store.accept('READY', const {'read_state': 'nonsense'}), isTrue);
    expect(store.snapshot.readStates, isEmpty);
    expect(store.snapshot.readStateVersion, 0);
    expect(
      store.accept('READY', const {'notification_settings': 'nonsense'}),
      isTrue,
    );
    expect(store.snapshot.accountNotificationFlags, 0);
  });

  test('MESSAGE_ACK moves the cursor forward and never back', () {
    final store = DiscordReadStateStore()..accept('READY', _ready());

    expect(
      store.accept('MESSAGE_ACK', {
        'channel_id': _channelId,
        'message_id': _newestMessage,
        'mention_count': 0,
        'version': 50,
      }),
      isTrue,
    );
    expect(store.channelState(_channelId).lastAckedId, _newestMessage);
    expect(store.channelState(_channelId).mentionCount, 0);
    expect(store.snapshot.readStateVersion, 50);

    store.accept('MESSAGE_ACK', {
      'channel_id': _channelId,
      'message_id': _olderMessage,
      'mention_count': 5,
      'version': 49,
    });
    expect(store.channelState(_channelId).lastAckedId, _newestMessage);
    expect(store.channelState(_channelId).mentionCount, 5);
    // An out-of-order dispatch must not walk the counter back, or the next
    // connect would ask for a delta it has already applied.
    expect(store.snapshot.readStateVersion, 50);
  });

  test('a manual MESSAGE_ACK is the one rewind that is honoured', () {
    final store = DiscordReadStateStore()..accept('READY', _ready());
    store.accept('MESSAGE_ACK', {
      'channel_id': _channelId,
      'message_id': _newestMessage,
    });

    store.accept('MESSAGE_ACK', {
      'channel_id': _channelId,
      'message_id': _olderMessage,
      'manual': true,
      'mention_count': 3,
    });

    expect(store.channelState(_channelId).lastAckedId, _olderMessage);
    expect(store.channelState(_channelId).mentionCount, 3);
  });

  test('ignores a MESSAGE_ACK with no channel or message', () {
    final store = DiscordReadStateStore();
    expect(store.accept('MESSAGE_ACK', const {'channel_id': 1}), isFalse);
    expect(
      store.accept('MESSAGE_ACK', const {'channel_id': _channelId}),
      isFalse,
    );
    expect(store.snapshot.readStates, isEmpty);
  });

  test('pin dispatches move the pin pointer, only one bumps the version', () {
    final store = DiscordReadStateStore();

    expect(
      store.accept('CHANNEL_PINS_ACK', {
        'channel_id': _channelId,
        'timestamp': '2026-07-20T10:00:00+00:00',
        'version': 12,
      }),
      isTrue,
    );
    expect(
      store.channelState(_channelId).lastPinTimestamp,
      DateTime.utc(2026, 7, 20, 10),
    );
    expect(store.snapshot.readStateVersion, 12);

    expect(
      store.accept('CHANNEL_PINS_UPDATE', {
        'channel_id': _channelId,
        'last_pin_timestamp': '2026-07-21T10:00:00+00:00',
        'version': 99,
      }),
      isTrue,
    );
    expect(
      store.channelState(_channelId).lastPinTimestamp,
      DateTime.utc(2026, 7, 21, 10),
    );
    expect(store.snapshot.readStateVersion, 12);

    expect(store.accept('CHANNEL_PINS_ACK', const {}), isFalse);
    expect(store.accept('CHANNEL_PINS_UPDATE', const {}), isFalse);
    store.accept('CHANNEL_PINS_UPDATE', const {'channel_id': _channelId});
    expect(store.channelState(_channelId).lastPinTimestamp, isNull);
  });

  test('GUILD_FEATURE_ACK acks a guild-scoped entity', () {
    final store = DiscordReadStateStore();

    expect(
      store.accept('GUILD_FEATURE_ACK', {
        'resource_id': _guildId,
        'ack_type': ReadStateType.guildOnboardingQuestion.wireValue,
        'entity_id': _guildId,
      }),
      isTrue,
    );
    final state = store.entityState(
      ReadStateType.guildOnboardingQuestion,
      _guildId,
    );
    expect(state.lastAckedId, _guildId);
    expect(state.mentionCount, 0);

    // Falls back to resource_id when the entity is not named separately.
    expect(
      store.accept('GUILD_FEATURE_ACK', {
        'resource_id': _guildId,
        'ack_type': ReadStateType.guildHome.wireValue,
      }),
      isTrue,
    );
    expect(
      store.entityState(ReadStateType.guildHome, _guildId).lastAckedId,
      _guildId,
    );
  });

  test('refuses an ack whose scope and type disagree', () {
    final store = DiscordReadStateStore();

    expect(
      store.accept('GUILD_FEATURE_ACK', {
        'ack_type': ReadStateType.messageRequests.wireValue,
        'entity_id': _guildId,
      }),
      isFalse,
    );
    expect(
      store.accept('USER_NON_CHANNEL_ACK', {
        'ack_type': ReadStateType.guildEvent.wireValue,
        'entity_id': _guildId,
      }),
      isFalse,
    );
    expect(
      store.accept('USER_NON_CHANNEL_ACK', {
        'ack_type': 6,
        'entity_id': _guildId,
      }),
      isFalse,
    );
    expect(
      store.accept('USER_NON_CHANNEL_ACK', {
        'ack_type': ReadStateType.messageRequests.wireValue,
        'entity_id': '',
      }),
      isFalse,
    );
    expect(store.snapshot.readStates, isEmpty);
  });

  test('USER_NON_CHANNEL_ACK acks an account-scoped entity', () {
    final store = DiscordReadStateStore();
    expect(
      store.accept('USER_NON_CHANNEL_ACK', {
        'ack_type': ReadStateType.notificationCenter.wireValue,
        'entity_id': _guildId,
      }),
      isTrue,
    );
    expect(
      store.entityState(ReadStateType.notificationCenter, _guildId).lastAckedId,
      _guildId,
    );
  });

  test('USER_GUILD_SETTINGS_UPDATE replaces one guild and bumps the max', () {
    final store = DiscordReadStateStore()..accept('READY', _ready());

    expect(
      store.accept('USER_GUILD_SETTINGS_UPDATE', {
        'guild_id': _guildId,
        'muted': false,
        'suppress_everyone': true,
        'version': 11,
      }),
      isTrue,
    );
    expect(store.settingsFor(_guildId).muted, isFalse);
    expect(store.settingsFor(_guildId).suppressEveryone, isTrue);
    expect(store.snapshot.userGuildSettingsVersion, 11);

    store.accept('USER_GUILD_SETTINGS_UPDATE', {
      'guild_id': _guildId,
      'muted': true,
      'version': 3,
    });
    expect(store.settingsFor(_guildId).muted, isTrue);
    expect(store.snapshot.userGuildSettingsVersion, 11);
  });

  test('ignores dispatches it does not model', () {
    final store = DiscordReadStateStore();
    expect(store.accept('MESSAGE_CREATE', const {}), isFalse);
    expect(store.snapshot.readStates, isEmpty);
  });

  test('put and putSettings replace outright, clear forgets everything', () {
    final store = DiscordReadStateStore()..accept('READY', _ready());

    store
      ..put(ReadState(entityId: _channelId, lastAckedId: _newestMessage))
      ..putSettings(
        GuildNotificationSettings(spaceId: _guildId, mobilePush: false),
      );
    expect(store.channelState(_channelId).lastAckedId, _newestMessage);
    expect(store.settingsFor(_guildId).mobilePush, isFalse);

    store.clear();
    expect(store.snapshot.readStates, isEmpty);
    expect(store.snapshot.settings, isEmpty);
    expect(store.snapshot.readStateVersion, 0);
    expect(store.snapshot.userGuildSettingsVersion, 0);
    expect(store.snapshot.accountNotificationFlags, 0);
    expect(store.channelState(_channelId).lastAckedId, isNull);
    expect(
      store.entityState(ReadStateType.guildEvent, _guildId).type,
      ReadStateType.guildEvent,
    );
  });
}

Map<String, Object?> _ready() => {
  'notification_settings': {
    'flags': AccountNotificationFlags.useNewNotifications,
  },
  'read_state': {
    'version': 42,
    'partial': false,
    'entries': [
      {
        'id': _channelId,
        'mention_count': 2,
        'last_message_id': _olderMessage,
        'flags': 1,
      },
      {
        'id': _guildId,
        'read_state_type': 1,
        'badge_count': 1,
        'last_acked_id': _newerMessage,
      },
      {'read_state_type': 0},
    ],
  },
  'user_guild_settings': {
    'version': 7,
    'partial': false,
    'entries': [
      {'guild_id': _guildId, 'muted': true},
      {'guild_id': null, 'suppress_everyone': true},
    ],
  },
};
