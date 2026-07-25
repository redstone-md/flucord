import 'package:flucord/src/data/discord/discord_desktop_rest_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds channel history query from the desktop route', () {
    final request = DiscordDesktopRestRequest.channelHistory(
      channelId: '100',
      before: '200',
      limit: 100,
    );

    expect(request.method, 'GET');
    expect(request.path, '/channels/100/messages');
    expect(request.query, {'before': '200', 'limit': '100'});
  });

  test('builds create, edit, and delete message requests', () {
    final create = DiscordDesktopRestRequest.createMessage(
      channelId: '100',
      content: 'hello',
      nonce: '300',
      flags: 4096,
      messageReference: {'message_id': '200'},
      stickerIds: const ['400'],
    );
    final edit = DiscordDesktopRestRequest.editMessage(
      channelId: '100',
      messageId: '200',
      content: 'edited',
    );
    final delete = DiscordDesktopRestRequest.deleteMessage(
      channelId: '100',
      messageId: '200',
    );

    expect(create.method, 'POST');
    expect(create.path, '/channels/100/messages');
    expect(create.body?['nonce'], '300');
    expect(create.body?['message_reference'], {'message_id': '200'});
    expect(edit.method, 'PATCH');
    expect(edit.path, '/channels/100/messages/200');
    expect(edit.body, {'content': 'edited'});
    expect(delete.method, 'DELETE');
    expect(delete.path, '/channels/100/messages/200');
  });

  test('builds individual and bulk read acknowledgements', () {
    final ack = DiscordDesktopRestRequest.ackMessage(
      channelId: '100',
      messageId: '200',
      readStateToken: 'next-token',
      lastViewed: 7,
      flags: 1,
    );
    final bulk = DiscordDesktopRestRequest.ackBulk(const [
      {'channel_id': '100', 'message_id': '200', 'read_state_type': 0},
    ]);

    expect(ack.path, '/channels/100/messages/200/ack');
    expect(ack.body?['token'], 'next-token');
    expect(bulk.path, '/read-states/ack-bulk');
    expect((bulk.body?['read_states'] as List), hasLength(1));
  });

  test('opens DMs with the desktop recipients payload', () {
    final request = DiscordDesktopRestRequest.openDirectMessage(const ['200']);

    expect(request.method, 'POST');
    expect(request.path, '/users/@me/channels');
    expect(request.body, {
      'recipients': ['200'],
    });
  });
}
