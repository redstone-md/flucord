import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000091';
const _notePath = '/api/v9/users/@me/notes/${SessionHarness.friendId}';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  testSession(
    'a note Discord saves with an empty answer reads as saved',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _messageId,
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'hello',
        ),
      );
      await tester.tap(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: _key('message-author-name'),
        ),
      );
      await session.settle();
      await tester.tap(_key('profile-card-avatar'));
      await session.settle();

      await tester.enterText(_key('profile-note-field'), 'met at the LAN');
      await session.settle();
      await tester.tap(_key('profile-note-save'));
      await session.settle();

      expect(
        session.transport.requests.where(
          (request) => request.method == 'PUT' && request.uri.path == _notePath,
        ),
        hasLength(1),
      );
      expect(_key('profile-note-refused'), findsNothing);
      expect(_key('profile-note-save'), findsNothing);
    },
    // How Discord answers a saved note: 204 and no body.
    routes: (transport) => transport.on(
      'PUT',
      _notePath,
      (_) => const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
    ),
  );
}
