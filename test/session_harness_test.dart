import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/build_counter.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelMessagesPath =
    '/api/v9/channels/${SessionHarness.channelId}/messages';
const _messageId = '900000000000000001';

Map<String, Object?> _message(String content) => rawMessage(
  id: _messageId,
  channelId: SessionHarness.channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: content,
);

void main() {
  testSession('a raw MESSAGE_CREATE appears as a message row', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);

    await session.dispatch('MESSAGE_CREATE', _message('hello from the wire'));

    expect(session.messageRow(_messageId), findsOneWidget);
    expect(find.textContaining('hello from the wire'), findsOneWidget);
  });

  testSession(
    'a routed history page shows when the channel opens',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      expect(find.textContaining('from the history route'), findsOneWidget);
    },
    routes: (transport) => transport.on(
      'GET',
      _channelMessagesPath,
      (_) => jsonResponse([_message('from the history route')]),
    ),
  );

  testSession('the client identifies on the socket with the saved session', (
    tester,
    session,
  ) async {
    final identify = session.socket.frames.singleWhere((f) => f['op'] == 2);

    expect((identify['d']! as Map)['token'], 'harness-token');
  });

  testSession('Enter in the composer posts the message over HTTP', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _channelMessagesPath,
      (_) => jsonResponse(_message('typed by the user')),
    );
    await session.openChannel(SessionHarness.channelId);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'typed by the user',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await session.settle();

    final post = session.transport.requests.singleWhere(
      (request) =>
          request.method == 'POST' && request.uri.path == _channelMessagesPath,
    );
    expect((post.json! as Map)['content'], 'typed by the user');
    expect(session.messageRow(_messageId), findsOneWidget);
  });

  testSession('a dropped connection dials a new socket that resumes', (
    tester,
    session,
  ) async {
    await session.socket.dropConnection(code: 1006);
    await tester.pump(const Duration(seconds: 2));
    await session.settle();
    expect(session.sockets, hasLength(2));

    await session.hello();

    expect(session.socket.frames.map((frame) => frame['op']), contains(6));
  });

  testSession('the composer shows the GIF button', (tester, session) async {
    await session.openChannel(SessionHarness.channelId);

    expect(find.byKey(const ValueKey('gif-picker-open')), findsOneWidget);
  });

  group('countBuilds', () {
    testWidgets('counts the builds of each widget type during the action', (
      tester,
    ) async {
      final leaf = GlobalKey<_LeafState>();
      await tester.pumpWidget(_Parent(child: _Leaf(key: leaf)));

      final builds = await countBuilds(() async {
        leaf.currentState!.rebuild();
        await tester.pump();
        leaf.currentState!.rebuild();
        await tester.pump();
      });

      expect(builds.of<_Leaf>(), 2);
      expect(builds.of<_Parent>(), 0);
    });

    testSession('sees the rows of the real timeline', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      final builds = await countBuilds(
        () => session.dispatch('MESSAGE_CREATE', _message('counted')),
      );

      expect(builds.of<MessageItem>(), greaterThan(0));
    });
  });
}

class _Parent extends StatelessWidget {
  const _Parent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Leaf extends StatefulWidget {
  const _Leaf({super.key});

  @override
  State<_Leaf> createState() => _LeafState();
}

class _LeafState extends State<_Leaf> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
