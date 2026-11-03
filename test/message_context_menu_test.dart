import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_context_menu.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  group('how the menu looks', () {
    testWidgets('sits one layer up: raised, a thin border, medium corners', (
      tester,
    ) async {
      await _pumpMenu(tester, isCurrentUser: false);
      final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

      final menu = _menuSurface(
        tester,
        find.byKey(const ValueKey('message-menu-reply')),
      );
      final shape = menu.shape! as RoundedRectangleBorder;
      expect(menu.color, surfaces.raised);
      expect(shape.side.color, surfaces.border);
      expect(shape.side.width, 1);
      expect(shape.borderRadius, FlucordRadius.medium);
    });

    testWidgets('rows are in the label role with an icon each', (
      tester,
    ) async {
      await _pumpMenu(tester, isCurrentUser: true);

      final reply = find.byKey(const ValueKey('message-menu-reply'));
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(of: reply, matching: find.byType(RichText)),
      );
      expect(label.text.style?.fontSize, FlucordTextRole.label.size);
      expect(
        find.descendant(of: reply, matching: find.byType(FlucordIcon)),
        findsOne,
      );
      final delete = find.byKey(const ValueKey('message-menu-delete'));
      expect(
        find.descendant(of: delete, matching: find.byType(FlucordIcon)),
        findsOne,
      );
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
          bypassesSlowmode: false,
        ),
        isCurrentUser: false,
      );

      // Reading is all this account can do, and a menu offering to reply into
      // a channel Discord will refuse is a menu that lies.
      expect(find.byKey(const ValueKey('message-menu-reply')), findsNothing);
      expect(find.byKey(const ValueKey('message-menu-delete')), findsNothing);
      expect(find.byKey(const ValueKey('message-menu-edit')), findsNothing);
      expect(
        find.byKey(const ValueKey('message-menu-add-reaction')),
        findsNothing,
      );
      // Copying is always on: it asks nothing of the server.
      expect(
        find.byKey(const ValueKey('message-menu-copy-id')),
        findsOneWidget,
      );
    });

    testWidgets('no Mark unread on a transport with no read state', (
      tester,
    ) async {
      await _pumpMenu(tester, isCurrentUser: false);

      expect(
        find.byKey(const ValueKey('message-menu-mark-unread')),
        findsNothing,
      );
    });

    testWidgets('its own message can be edited and deleted', (tester) async {
      await _pumpMenu(tester, isCurrentUser: true);

      expect(find.byKey(const ValueKey('message-menu-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-reply')), findsOneWidget);
    });

    // Discord refuses an edit to a voice message, so the menu does not offer
    // an editor that could never save.
    testWidgets('its own voice message can be deleted, not edited', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        message: _message.copyWith(flags: DiscordMessageFlag.voiceMessage.bit),
        isCurrentUser: true,
      );

      expect(find.byKey(const ValueKey('message-menu-edit')), findsNothing);
      expect(find.byKey(const ValueKey('message-menu-delete')), findsOneWidget);
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
          bypassesSlowmode: false,
        ),
        isCurrentUser: false,
      );

      expect(find.byKey(const ValueKey('message-menu-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-menu-edit')), findsNothing);
    });
  });
}

/// The surface the open menu is drawn on: the nearest [Material] above
/// [item] that has a shape of its own.
Material _menuSurface(WidgetTester tester, Finder item) => tester
    .widgetList<Material>(
      find.ancestor(of: item, matching: find.byType(Material)),
    )
    .firstWhere((material) => material.shape is RoundedRectangleBorder);

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
    bypassesSlowmode: false,
  ),
  ChatMessage? message,
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
              message: message ?? _message,
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
