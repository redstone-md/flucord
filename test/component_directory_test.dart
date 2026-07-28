import 'dart:async';

import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/presentation/widgets/component_directory_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _workspace = ChatWorkspace(
  spaces: [
    const CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'F',
      colorValue: 0,
    ),
  ],
  channels: [
    const ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
    const ConversationChannel(
      id: 'lounge',
      spaceId: 'guild-1',
      name: 'lounge',
      topic: '',
      kind: ChannelKind.voice,
    ),
    const ConversationChannel(
      id: 'ideas',
      spaceId: 'guild-1',
      name: 'ideas',
      topic: '',
      kind: ChannelKind.forum,
    ),
    const ConversationChannel(
      id: 'clips',
      spaceId: 'guild-1',
      name: 'clips',
      topic: '',
      kind: ChannelKind.media,
    ),
    const ConversationChannel(
      id: 'thread-1',
      spaceId: 'guild-1',
      name: 'a thread',
      topic: '',
      kind: ChannelKind.text,
      isThread: true,
    ),
    // Another server's channel is not on offer here.
    const ConversationChannel(
      id: 'elsewhere',
      spaceId: 'guild-2',
      name: 'elsewhere',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: [
    const Member(
      id: 'member-1',
      displayName: 'Rx',
      initials: 'R',
      role: 'Maintainer',
      presence: Presence.online,
      colorValue: 0,
    ),
    const Member(
      id: 'member-2',
      displayName: 'Sam',
      initials: 'S',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0,
    ),
  ],
  roles: [
    const CommunityRole(
      id: 'role-1',
      spaceId: 'guild-1',
      name: 'Admin',
      position: 1,
    ),
    const CommunityRole(
      id: 'role-2',
      spaceId: 'guild-2',
      name: 'Elsewhere',
      position: 1,
    ),
  ],
  messages: const [],
  currentMemberId: 'member-1',
);

List<DirectoryEntry> _entries(int type) => ComponentDirectory.entriesFor(
  MessageComponent(type: type, customId: 'pick'),
  workspace: _workspace,
  spaceId: 'guild-1',
);

void main() {
  group('directory', () {
    test('a user select offers the workspace members', () {
      final entries = _entries(5);

      expect(entries.map((entry) => entry.id), ['member-1', 'member-2']);
      expect(entries.first.label, 'Rx');
      expect(entries.first.detail, 'Maintainer');
    });

    test('a role select offers only this server\'s roles', () {
      expect(_entries(6).map((entry) => entry.id), ['role-1']);
    });

    test('a mentionable select offers both, members first', () {
      expect(_entries(7).map((entry) => entry.id), [
        'member-1',
        'member-2',
        'role-1',
      ]);
    });

    test('a channel select names what each channel is', () {
      final entries = _entries(8);

      expect(entries.map((entry) => entry.id), [
        'general',
        'lounge',
        'ideas',
        'clips',
        'thread-1',
      ]);
      expect(entries.map((entry) => entry.detail), [
        'Text',
        'Voice',
        'Forum',
        'Media',
        'Thread',
      ]);
    });

    test('a string select resolves against nothing', () {
      // Its choices come from the application, not from the server.
      expect(_entries(3), isEmpty);
      expect(_entries(2), isEmpty);
    });
  });

  group('picker', () {
    /// Pumps a host and hands back its context. Awaiting the dialog's own
    /// future here would deadlock: it does not complete until the dialog is
    /// closed, and closing it is what the test does next.
    Future<BuildContext> host(WidgetTester tester) async {
      late BuildContext dialogContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                dialogContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return dialogContext;
    }

    testWidgets('chooses one entry', (tester) async {
      final result = ComponentDirectoryPicker.show(
        await host(tester),
        title: 'Pick a member',
        entries: _entries(5),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pick a member'), findsOne);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('directory-confirm')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('directory-entry-member-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-confirm')));
      await tester.pumpAndSettle();

      expect(await result, ['member-2']);
    });

    testWidgets('a single-value select swaps rather than refusing', (
      tester,
    ) async {
      final result = ComponentDirectoryPicker.show(
        await host(tester),
        title: 'Pick a member',
        entries: _entries(5),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('directory-entry-member-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-entry-member-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-confirm')));
      await tester.pumpAndSettle();

      expect(await result, ['member-2']);
    });

    testWidgets('a multi-value select keeps both, and untoggles', (
      tester,
    ) async {
      final result = ComponentDirectoryPicker.show(
        await host(tester),
        title: 'Pick a member',
        entries: _entries(5),
        maxValues: 2,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('directory-entry-member-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-entry-member-2')));
      await tester.pumpAndSettle();
      // Tapping a chosen row takes it back off.
      await tester.tap(find.byKey(const ValueKey('directory-entry-member-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-entry-member-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory-confirm')));
      await tester.pumpAndSettle();

      expect(await result, ['member-2', 'member-1']);
    });

    testWidgets('searches by name and by detail', (tester) async {
      unawaited(
        ComponentDirectoryPicker.show(
          await host(tester),
          title: 'Pick a member',
          entries: _entries(5),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('directory-search')),
        'maintainer',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('directory-entry-member-1')), findsOne);
      expect(
        find.byKey(const ValueKey('directory-entry-member-2')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('directory-search')),
        'sam',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('directory-entry-member-2')), findsOne);

      await tester.enterText(
        find.byKey(const ValueKey('directory-search')),
        'nobody',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('directory-empty')), findsOne);
    });

    testWidgets('closing answers nothing', (tester) async {
      final result = ComponentDirectoryPicker.show(
        await host(tester),
        title: '',
        entries: _entries(6),
      );
      await tester.pumpAndSettle();

      // With no placeholder the picker still names itself.
      expect(find.text('Choose'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('directory-cancel')));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });
  });
}
