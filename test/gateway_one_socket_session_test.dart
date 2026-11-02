import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _opReconnect = {'op': 7, 'd': null};
const _opResume = 6;

/// Longer than the wait before the client redials after a closed socket, so a
/// reconnect a test should not have started has time to happen.
const _pastRedialDelay = Duration(seconds: 3);

void main() {
  testSession(
    'opcode 7 leaves one open socket when the old one finishes closing '
    'during the dial',
    (tester, session) async {
      final old = session.socket..holdClose();
      session.connector.holdDials();

      old.receive(_opReconnect);
      await session.settle();
      await old.completeClose();
      await session.settle();
      await tester.pump(_pastRedialDelay);
      await session.settle();
      session.connector.releaseDials();
      await session.settle();

      expect(session.connector.dials, 2);
      expect(session.sockets.where((socket) => socket.isOpen), [
        session.socket,
      ]);
    },
  );

  testSession('a late close from the old socket leaves the new one healthy', (
    tester,
    session,
  ) async {
    final old = session.socket..holdClose();

    old.receive(_opReconnect);
    await session.settle();
    final fresh = session.socket;
    await session.hello();
    await old.completeClose();
    await session.settle();
    await tester.pump(_pastRedialDelay);
    await session.settle();

    expect(fresh.isOpen, isTrue);
    expect(session.connector.dials, 2);
    expect(
      fresh.frames.where((frame) => frame['op'] == _opResume),
      hasLength(1),
    );
  });

  testSession('a late error from the old socket leaves the new one healthy', (
    tester,
    session,
  ) async {
    final old = session.socket..holdClose();

    old.receive(_opReconnect);
    await session.settle();
    final fresh = session.socket;
    await session.hello();
    old.failConnection(StateError('the old connection failed'));
    await session.settle();
    await tester.pump(_pastRedialDelay);
    await session.settle();

    expect(fresh.isOpen, isTrue);
    expect(session.connector.dials, 2);
  });

  testSession(
    'a dial race leaves one socket to replay on, so a message shows one toast',
    (tester, session) async {
      final old = session.socket..holdClose();
      session.connector.holdDials();

      old.receive(_opReconnect);
      await session.settle();
      await old.completeClose();
      await session.settle();
      await tester.pump(_pastRedialDelay);
      await session.settle();
      session.connector.releaseDials();
      await session.settle();

      // The server replays what was missed on every socket that resumes.
      for (final socket in session.sockets.where((socket) => socket.isOpen)) {
        socket.receive({
          'op': 0,
          's': session.sequence + 1,
          't': 'MESSAGE_CREATE',
          'd': _friendMessage('900000000000000001'),
        });
      }
      await session.settle();

      expect(session.toasts, hasLength(1));
    },
  );

  testSession(
    'a message on the old socket is left for the replay, which shows one toast',
    (tester, session) async {
      final old = session.socket..holdClose();
      final lastSeen = session.sequence;
      final missed = _friendMessage('900000000000000001');

      old.receive(_opReconnect);
      old.receive({
        'op': 0,
        's': lastSeen + 1,
        't': 'MESSAGE_CREATE',
        'd': missed,
      });
      await session.settle();
      await session.hello();

      final resume = session.socket.frames.singleWhere(
        (frame) => frame['op'] == _opResume,
      );
      expect((resume['d']! as Map<String, Object?>)['seq'], lastSeen);

      await session.dispatch('MESSAGE_CREATE', missed);

      expect(session.toasts, hasLength(1));
    },
  );

  testSession('signing out during a dial closes that socket when it returns', (
    tester,
    session,
  ) async {
    session.connector.holdDials();
    await session.socket.dropConnection();
    await session.settle();
    await tester.pump(const Duration(seconds: 2));
    await session.settle();
    expect(session.connector.dials, 2);

    await session.signOut();
    session.connector.releaseDials();
    await session.settle();

    expect(session.sockets, hasLength(2));
    expect(session.socket.isOpen, isFalse);
    expect(session.socket.frames, isEmpty);
  });

  test('a second connect during a dial starts no second dial', () async {
    final connector = MemoryDesktopWebSocketConnector()..holdDials();
    final gateway = DiscordDesktopGatewayClient(
      authorization: SessionHarness.tokenOf(SessionHarness.currentUserId),
      properties: const {},
      socketConnector: connector,
    );
    addTearDown(gateway.close);

    final first = gateway.connect('wss://gateway.discord.gg');
    final second = gateway.connect('wss://gateway.discord.gg');
    connector.releaseDials();
    await Future.wait([first, second]);

    expect(connector.sockets, hasLength(1));
  });
}

Map<String, Object?> _friendMessage(String id) => rawMessage(
  id: id,
  channelId: SessionHarness.dmChannelId,
  authorId: SessionHarness.friendId,
  content: 'hello',
);
