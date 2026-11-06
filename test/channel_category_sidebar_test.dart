import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/participant_menu.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/flucord_icon_finder.dart';
import 'support/stream_room_harness.dart';

void main() {
  testWidgets('collapses categories but retains selected and unread channels', (
    tester,
  ) async {
    final controller = WorkspaceController()..reconcile(_workspace);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => ChannelSidebar(
              space: _workspace.spaces.single,
              channels: _workspace.channels,
              selectedChannelId: controller.selectedChannelId,
              onSelectChannel: controller.selectChannel,
              sessionMode: SessionMode.demo,
              connectionStatus: RepositoryConnectionStatus.connected,
              categories: _workspace.categoriesFor(_workspace.spaces.single.id),
              currentMember: _workspace.memberById(_workspace.currentMemberId),
              memberOf: _workspace.memberOrNull,
              channelOf: _workspace.channelOrNull,
              collapsedCategoryIds: controller.collapsedCategoryIds,
              onToggleCategory: controller.toggleCategory,
              onNewDirectMessage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('OPERATIONS'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-random')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);

    final mention = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('channel-mention-alerts')),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      (mention.decoration as BoxDecoration).color,
      FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.danger,
    );

    await tester.tap(find.byKey(const ValueKey('category-category-1')));
    await tester.pump();

    expect(controller.collapsedCategoryIds, contains('category-1'));
    expect(find.byKey(const ValueKey('channel-general')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-alerts')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-random')), findsNothing);
    expect(findFlucordIcon(FlucordIcons.chevronRight), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-category-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('channel-random')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a voice channel inside a category shows who is in it', (
    tester,
  ) async {
    final opened = <String>[];
    final (:controller, :voice) = await _pumpSeats(tester, opened);

    // Seats only rendered for channels outside a category, which is where
    // almost no server puts its voice channels, so nobody ever appeared.
    expect(
      find.byKey(const ValueKey('voice-seat-the-lodge-bot-1')),
      findsOneWidget,
    );

    // And they open: the left button opens the profile, as on Discord.
    await tester.tap(find.byKey(const ValueKey('voice-seat-the-lodge-bot-1')));
    await tester.pumpAndSettle();
    expect(opened, ['bot-1']);

    // The right button opens the participant menu, the same one a tile has.
    await tester.tap(
      find.byKey(const ValueKey('voice-seat-the-lodge-friend-1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(opened, ['bot-1']);
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(voice.volumeFor('friend-1'), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('category-category-1')));
    await tester.pump();

    // A collapsed category hides the occupants with the channel.
    expect(
      find.byKey(const ValueKey('voice-seat-the-lodge-bot-1')),
      findsNothing,
    );
  });

  for (final key in [
    const SingleActivator(LogicalKeyboardKey.contextMenu),
    const SingleActivator(LogicalKeyboardKey.f10, shift: true),
  ]) {
    testWidgets('${key.trigger.keyLabel} opens the menu on a focused seat', (
      tester,
    ) async {
      await _pumpSeats(tester, []);
      final seat = find.byKey(const ValueKey('voice-seat-the-lodge-friend-1'));
      Focus.of(
        tester.element(
          find.descendant(of: seat, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await tester.pump();

      if (key.shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(key.trigger);
      if (key.shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(find.text('User volume'), findsOneWidget);
    });
  }
}

/// Pumps the sidebar of [_workspace] with two people seated in its voice
/// channel. A left click on a seat adds its user to [opened].
Future<({WorkspaceController controller, VoiceController voice})> _pumpSeats(
  WidgetTester tester,
  List<String> opened,
) async {
  final controller = WorkspaceController()..reconcile(_workspace);
  final voice = VoiceController(StreamRoomMedia());
  addTearDown(voice.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ChannelSidebar(
            space: _workspace.spaces.single,
            channels: _workspace.channels,
            selectedChannelId: controller.selectedChannelId,
            onSelectChannel: controller.selectChannel,
            sessionMode: SessionMode.demo,
            connectionStatus: RepositoryConnectionStatus.connected,
            categories: _workspace.categoriesFor(_workspace.spaces.single.id),
            currentMember: _workspace.memberById(_workspace.currentMemberId),
            memberOf: _workspace.memberOrNull,
            channelOf: _workspace.channelOrNull,
            collapsedCategoryIds: controller.collapsedCategoryIds,
            onToggleCategory: controller.toggleCategory,
            onNewDirectMessage: () {},
            onOpenMemberProfile: (userId, _) => opened.add(userId),
            participantMenu: ParticipantMenu(
              voice: voice,
              currentMemberId: _workspace.currentMemberId,
            ),
            seatedByChannel: const {
              'the-lodge': [
                VoiceParticipantStateEvent(
                  userId: 'bot-1',
                  channelId: 'the-lodge',
                  guildId: 'guild-1',
                  selfMuted: false,
                  selfDeafened: false,
                  serverMuted: false,
                  serverDeafened: false,
                  isStreaming: false,
                  isVideoEnabled: false,
                ),
                VoiceParticipantStateEvent(
                  userId: 'friend-1',
                  channelId: 'the-lodge',
                  guildId: 'guild-1',
                  selfMuted: false,
                  selfDeafened: false,
                  serverMuted: false,
                  serverDeafened: false,
                  isStreaming: false,
                  isVideoEnabled: false,
                ),
              ],
            },
          ),
        ),
      ),
    ),
  );
  return (controller: controller, voice: voice);
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  categories: const [
    ChannelCategory(
      id: 'category-1',
      spaceId: 'guild-1',
      name: 'Operations',
      position: 1,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      position: 1,
      parentId: 'category-1',
    ),
    ConversationChannel(
      id: 'alerts',
      spaceId: 'guild-1',
      name: 'alerts',
      topic: '',
      kind: ChannelKind.text,
      position: 2,
      parentId: 'category-1',
      unread: true,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'the-lodge',
      spaceId: 'guild-1',
      name: 'The Lodge',
      topic: '',
      kind: ChannelKind.voice,
      position: 4,
      parentId: 'category-1',
    ),
    ConversationChannel(
      id: 'random',
      spaceId: 'guild-1',
      name: 'random',
      topic: '',
      kind: ChannelKind.text,
      position: 3,
      parentId: 'category-1',
    ),
  ],
  members: const [
    Member(
      id: 'bot-1',
      displayName: 'Flucord Bot',
      initials: 'FB',
      role: 'Discord bot',
      presence: Presence.online,
      colorValue: 0xff5865f2,
    ),
  ],
  messages: const [],
  currentMemberId: 'bot-1',
);
