import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/composer_autocomplete_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/composer_draft.dart';
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

  testWidgets('a colon offers emoji from both servers and the catalogue', (
    tester,
  ) async {
    await tester.pumpWidget(_composerApp());
    final composer = find.byKey(const ValueKey('message-composer'));

    await tester.enterText(composer, ':forge_s');
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-autocomplete')), findsOneWidget);
    expect(find.text('EMOJI'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-suggestion-emoji-forge-spark')),
      findsOneWidget,
    );
    // The server that owns it is what the row says beside the name.
    expect(find.text('Forge'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_composerText(tester), '<:forge_spark:forge-spark> ');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
  });

  testWidgets('a colon inserts a unicode glyph in place of the name', (
    tester,
  ) async {
    await tester.pumpWidget(_composerApp());
    final composer = find.byKey(const ValueKey('message-composer'));

    await tester.enterText(composer, ':rocket');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-suggestion-emoji-unicode-rocket')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('composer-suggestion-emoji-unicode-rocket')),
    );
    await tester.pump();

    expect(_composerText(tester), '🚀 ');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
  });

  testWidgets('Numpad Enter sends, as Enter does', (tester) async {
    final sentBodies = <String>[];
    await tester.pumpWidget(_composerApp(sentBodies: sentBodies));

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'from the number pad',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();

    expect(sentBodies, ['from the number pad']);
    expect(_composerText(tester), isEmpty);
  });

  testWidgets('Numpad Enter takes the selected suggestion', (tester) async {
    final sentBodies = <String>[];
    await tester.pumpWidget(_composerApp(sentBodies: sentBodies));

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      '@mi',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(sentBodies, isEmpty);
    expect(_composerText(tester), '<@member-1> ');
  });

  testWidgets('the selected suggestion stays in view as the arrows move it', (
    tester,
  ) async {
    await tester.pumpWidget(_composerApp(workspace: _crowdedWorkspace));
    final menu = find.byKey(const ValueKey('composer-autocomplete'));
    Finder row(int index) =>
        find.byKey(ValueKey('composer-suggestion-member-crowd-$index'));

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      '@crowd',
    );
    await tester.pump();
    expect(row(7), findsNothing);

    for (var press = 0; press < 7; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pump();

    expect(row(7), findsOneWidget);
    expect(
      tester.getBottomLeft(row(7)).dy,
      lessThanOrEqualTo(tester.getBottomLeft(menu).dy),
    );

    // Down from the last row wraps to the first.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    expect(row(0), findsOneWidget);
    expect(
      tester.getTopLeft(row(0)).dy,
      greaterThanOrEqualTo(tester.getTopLeft(menu).dy),
    );
  });
}

String _composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('message-composer')))
    .controller!
    .text;

Widget _composerApp({List<String>? sentBodies, ChatWorkspace? workspace}) =>
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageComposer(
            drafts: MemoryComposerDraftStore(),
            channelId: 'general',
            channelName: 'general',
            spaceName: 'Forge',
            autocompleteCatalog: ComposerAutocompleteCatalog.fromWorkspace(
              workspace ?? _workspace,
              (workspace ?? _workspace).channelById('general'),
            ),
            emojiSections: const [],
            stickerSections: const [],
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
    CommunitySpace(
      id: 'guild-2',
      name: 'Night Shift',
      monogram: 'NS',
      colorValue: 0xff765341,
    ),
  ],
  emojis: const [
    GuildEmoji(id: 'forge-spark', spaceId: 'guild-1', name: 'forge_spark'),
    GuildEmoji(id: 'relay-horn', spaceId: 'guild-2', name: 'relay_horn'),
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

/// More people match `@crowd` than the suggestion list shows at once.
final _crowdedWorkspace = _workspace.copyWith(
  members: [
    ..._workspace.members,
    for (var index = 0; index < 8; index++)
      Member(
        id: 'crowd-$index',
        displayName: 'Crowd $index',
        initials: 'C$index',
        role: 'Member',
        presence: Presence.online,
        colorValue: 0xff5865f2,
        spaceIds: const {'guild-1'},
      ),
  ],
);
