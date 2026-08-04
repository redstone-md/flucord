import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_context_menu.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _message = ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: 'them',
  body: 'the body',
  sentAt: DateTime.utc(2024),
);

void main() {
  group('the link a message copies', () {
    test('names the guild, the channel and the message', () {
      expect(
        messageLink(
          spaceId: 'guild-1',
          channelId: 'channel-1',
          messageId: 'message-1',
        ),
        'https://discord.com/channels/guild-1/channel-1/message-1',
      );
    });

    test('a direct message is @me, the way Discord writes it', () {
      // A DM has no guild, and a link naming an empty one resolves to nothing.
      for (final spaceId in ['', 'direct-messages']) {
        expect(
          messageLink(
            spaceId: spaceId,
            channelId: 'dm-1',
            messageId: 'message-1',
          ),
          'https://discord.com/channels/@me/dm-1/message-1',
        );
      }
    });
  });

  group('copying', () {
    testWidgets('an empty body puts nothing on the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );

      expect(await copyToClipboard(''), isFalse);
      expect(await copyToClipboard('something'), isTrue);
      expect(copied, ['something']);
    });
  });

  group('what the menu offers', () {
    testWidgets('only what this account may do here', (tester) async {
      await _pumpMenu(
        tester,
        capabilities: const ChannelCapabilities(
          viewChannel: true,
          sendMessages: false,
          manageMessages: false,
          pinMessages: false,
          createPublicThreads: false,
          addReactions: false,
          attachFiles: false,
          embedLinks: false,
          moderateStage: false,
        ),
        isCurrentUser: false,
      );

      // Reading is all this account can do, and a menu offering to reply into
      // a channel Discord will refuse is a menu that lies.
      expect(find.byKey(const ValueKey('message-menu-reply')), findsNothing);
      expect(find.byKey(const ValueKey('message-menu-delete')), findsNothing);
      expect(find.byKey(const ValueKey('message-menu-edit')), findsNothing);
      // Copying is always on: it asks nothing of the server.
      expect(
        find.byKey(const ValueKey('message-menu-copy-id')),
        findsOneWidget,
      );
    });

    testWidgets('its own message can be edited and deleted', (tester) async {
      await _pumpMenu(tester, isCurrentUser: true);

      expect(find.byKey(const ValueKey('message-menu-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-reply')), findsOneWidget);
    });

    testWidgets('a moderator deletes what is not theirs', (tester) async {
      await _pumpMenu(
        tester,
        capabilities: const ChannelCapabilities(
          viewChannel: true,
          sendMessages: true,
          manageMessages: true,
          pinMessages: true,
          createPublicThreads: true,
          addReactions: true,
          attachFiles: true,
          embedLinks: true,
          moderateStage: false,
        ),
        isCurrentUser: false,
      );

      expect(find.byKey(const ValueKey('message-menu-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-edit')), findsNothing);
    });
  });
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  ChannelCapabilities capabilities = const ChannelCapabilities(
    viewChannel: true,
    sendMessages: true,
    manageMessages: false,
    pinMessages: true,
    createPublicThreads: true,
    addReactions: true,
    attachFiles: true,
    embedLinks: true,
    moderateStage: false,
  ),
  required bool isCurrentUser,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessageContextMenu(
              context: context,
              position: const Offset(20, 20),
              message: _message,
              capabilities: capabilities,
              isCurrentUser: isCurrentUser,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
