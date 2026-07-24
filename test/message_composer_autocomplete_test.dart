import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/composer_autocomplete_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('selects a member with Enter without sending the query', (
    tester,
  ) async {
    final sentBodies = <String>[];
    await tester.pumpWidget(_composerApp(sentBodies: sentBodies));

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      '@mi',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-autocomplete')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-suggestion-member-member-1')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentBodies, isEmpty);
    expect(_composerText(tester), '<@member-1> ');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
  });

  testWidgets('uses arrow navigation for roles then sends exact syntax', (
    tester,
  ) async {
    final sentBodies = <String>[];
    await tester.pumpWidget(_composerApp(sentBodies: sentBodies));
    final composer = find.byKey(const ValueKey('message-composer'));

    await tester.enterText(composer, '@mod');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_composerText(tester), '<@&role-1> ');
    await tester.enterText(composer, '<@&role-1> deploy now');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sentBodies, ['<@&role-1> deploy now']);
    expect(_composerText(tester), isEmpty);
  });

  testWidgets('Escape dismisses suggestions without changing text', (
    tester,
  ) async {
    await tester.pumpWidget(_composerApp());

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Ping @mi',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
    expect(_composerText(tester), 'Ping @mi');
  });

  testWidgets('mouse selects a channel suggestion at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_composerApp());

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      '#voi',
    );
    await tester.pump();
    final composerRect = tester.getRect(
      find.byKey(const ValueKey('message-composer')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('composer-autocomplete')),
    );
    expect(menuRect.left, composerRect.left);
    expect(menuRect.right, composerRect.right);
    expect(menuRect.top, greaterThanOrEqualTo(0));
    expect(menuRect.bottom, lessThanOrEqualTo(composerRect.top));
    await tester.tap(
      find.byKey(const ValueKey('composer-suggestion-channel-voice')),
    );
    await tester.pump();

    expect(_composerText(tester), '<#voice> ');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('message-composer')))
    .controller!
    .text;

Widget _composerApp({List<String>? sentBodies}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: MessageComposer(
        channelId: 'general',
        channelName: 'general',
        spaceName: 'Forge',
        autocompleteCatalog: ComposerAutocompleteCatalog.fromWorkspace(
          _workspace,
          _workspace.channelById('general'),
        ),
        customEmojis: const [],
        guildStickers: const [],
        isSending: false,
        onSend: (body, _, _, _) async {
          sentBodies?.add(body);
          return true;
        },
        onCreatePoll: (_) async => false,
        onSendStickers: (_) async => false,
        onCancelReply: () {},
        onTyping: () {},
      ),
    ),
  ),
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff5865f2,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      position: 0,
    ),
    ConversationChannel(
      id: 'voice',
      spaceId: 'guild-1',
      name: 'voice-lab',
      topic: '',
      kind: ChannelKind.voice,
      position: 1,
    ),
  ],
  members: const [
    Member(
      id: 'member-1',
      displayName: 'Mira Stone',
      initials: 'MS',
      role: 'Moderator',
      presence: Presence.online,
      colorValue: 0xff57f287,
      spaceIds: {'guild-1'},
      rolesBySpace: {'guild-1': 'Moderator'},
    ),
  ],
  roles: const [
    CommunityRole(
      id: 'role-1',
      spaceId: 'guild-1',
      name: 'Moderator',
      position: 10,
      colorValue: 0xff57f287,
    ),
  ],
  messages: const [],
  currentMemberId: 'member-1',
);
