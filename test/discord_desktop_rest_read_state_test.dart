import 'package:flucord/src/data/discord/discord_desktop_rest_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _messageId = '234567890123456789';

void main() {
  test('omits the ack fields that do not apply', () {
    final first = DiscordDesktopRestRequest.ackMessage(
      channelId: _channelId,
      messageId: _messageId,
    );
    expect(first.body, {'token': null});

    final full = DiscordDesktopRestRequest.ackMessage(
      channelId: _channelId,
      messageId: _messageId,
      readStateToken: 'rolling',
      lastViewed: 2400,
      flags: 1,
    );
    expect(full.body, {'token': 'rolling', 'last_viewed': 2400, 'flags': 1});

    final tokenless = DiscordDesktopRestRequest.ackMessage(
      channelId: _channelId,
      messageId: _messageId,
      includeToken: false,
      lastViewed: 2400,
    );
    expect(tokenless.body, {'last_viewed': 2400});
  });

  test('rebuilds every bulk entry instead of forwarding it', () {
    final request = DiscordDesktopRestRequest.ackBulk([
      {
        'channel_id': _channelId,
        'message_id': _messageId,
        'read_state_type': 1,
        'unexpected': 'dropped',
      },
      {'channel_id': _channelId, 'message_id': _messageId},
    ]);

    expect(request.method, 'POST');
    expect(request.path, '/read-states/ack-bulk');
    expect(request.body, {
      'read_states': [
        {
          'channel_id': _channelId,
          'message_id': _messageId,
          'read_state_type': 1,
        },
        {
          'channel_id': _channelId,
          'message_id': _messageId,
          'read_state_type': 0,
        },
      ],
    });
  });

  test('refuses a bulk batch that is malformed or oversized', () {
    expect(
      () => DiscordDesktopRestRequest.ackBulk([
        {'channel_id': 'not-a-snowflake', 'message_id': _messageId},
      ]),
      throwsArgumentError,
    );
    expect(
      () => DiscordDesktopRestRequest.ackBulk([
        {
          'channel_id': _channelId,
          'message_id': _messageId,
          'read_state_type': 7,
        },
      ]),
      throwsArgumentError,
    );
    expect(
      () => DiscordDesktopRestRequest.ackBulk([
        for (
          var index = 0;
          index <= DiscordDesktopRestRequest.maxBulkAckEntries;
          index++
        )
          {'channel_id': _channelId, 'message_id': _messageId},
      ]),
      throwsArgumentError,
    );
  });

  test('marks unread with the manual body only', () {
    final request = DiscordDesktopReadStateRequests.markUnread(
      channelId: _channelId,
      messageId: _messageId,
      mentionCount: 2,
    );
    expect(request.method, 'POST');
    expect(request.path, '/channels/$_channelId/messages/$_messageId/ack');
    expect(request.body, {'manual': true, 'mention_count': 2});
    expect(
      () => DiscordDesktopReadStateRequests.markUnread(
        channelId: _channelId,
        messageId: _messageId,
        mentionCount: -1,
      ),
      throwsArgumentError,
    );
  });

  test('renders the guild ack with the type before the entity', () {
    final request = DiscordDesktopReadStateRequests.ackGuildEntity(
      guildId: _guildId,
      readStateType: 4,
      entityId: _guildId,
    );
    expect(request.method, 'POST');
    expect(request.path, '/guilds/$_guildId/ack/4/$_guildId');
    expect(request.body, isEmpty);
  });

  test('renders the user ack with the numeric type in the path', () {
    final request = DiscordDesktopReadStateRequests.ackUserEntity(
      readStateType: 5,
      entityId: _guildId,
    );
    expect(request.path, '/users/@me/5/$_guildId/ack');
    expect(request.body, isEmpty);
  });

  test('refuses a read-state type outside the enum', () {
    expect(
      () => DiscordDesktopReadStateRequests.ackUserEntity(
        readStateType: -1,
        entityId: _guildId,
      ),
      throwsArgumentError,
    );
    expect(
      () => DiscordDesktopReadStateRequests.ackGuildEntity(
        guildId: _guildId,
        readStateType: 6,
        entityId: _guildId,
      ),
      throwsArgumentError,
    );
  });

  test('deletes a read state with the versioned body', () {
    final request = DiscordDesktopReadStateRequests.deleteReadState(
      channelId: _channelId,
      readStateType: 0,
    );
    expect(request.method, 'DELETE');
    expect(request.path, '/channels/$_channelId/messages/ack');
    expect(request.body, {'version': 2, 'read_state_type': 0});
  });

  test('acks pins with no body at all', () {
    final request = DiscordDesktopReadStateRequests.ackPins(_channelId);
    expect(request.method, 'POST');
    expect(request.path, '/channels/$_channelId/pins/ack');
    expect(request.body, isNull);
  });

  test('patches the DM pseudo-guild through the single-guild route', () {
    final request = DiscordDesktopReadStateRequests.guildNotificationSettings(
      guildId: DiscordDesktopReadStateRequests.directMessagesGuildKey,
      settings: const {'muted': true},
    );
    expect(request.method, 'PATCH');
    expect(request.path, '/users/@me/guilds/@me/settings');
    expect(request.body, {'muted': true});
  });

  test('patches guilds in bulk and strips the favourites pseudo-guild', () {
    final request = DiscordDesktopReadStateRequests.bulkNotificationSettings({
      _guildId: const {'muted': true},
      DiscordDesktopReadStateRequests.favoritesGuildKey: const {'muted': true},
    });
    expect(request.method, 'PATCH');
    expect(request.path, '/users/@me/guilds/settings');
    expect(request.body, {
      'guilds': {
        _guildId: {'muted': true},
      },
    });
  });

  test('refuses a settings route addressed to a non-snowflake guild', () {
    expect(
      () => DiscordDesktopReadStateRequests.guildNotificationSettings(
        guildId: 'forge',
        settings: const {},
      ),
      throwsArgumentError,
    );
  });

  test('patches the account-wide notification flags', () {
    final request = DiscordDesktopReadStateRequests.accountNotificationSettings(
      48,
    );
    expect(request.method, 'PATCH');
    expect(request.path, '/users/@me/notification-settings');
    expect(request.body, {'flags': 48});
  });
}
