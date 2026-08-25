import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/notification_settings_menu.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '111111111111111111';
const _generalId = '222222222222222222';
const _alertsId = '333333333333333333';
const _memberId = '987654321098765432';
const _forumId = '123456789012345678';
const _mediaId = '234567890123456789';

/// Reused from the guild id: the fixture snowflake allow-list is short, and a
/// voice channel never shares a lookup namespace with the space itself here.
const _voiceId = _guildId;

void main() {
  testWidgets('dims a muted channel and marks it with the bell icon', (
    tester,
  ) async {
    await _pumpSidebar(tester, readState: _mutedChannelSnapshot());

    expect(
      find.byKey(const ValueKey('channel-muted-$_generalId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('channel-muted-$_alertsId')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mutes the whole space and says so in the header', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      readState: ReadStateSnapshot(
        settings: {
          _guildId: GuildNotificationSettings(spaceId: _guildId, muted: true),
        },
      ),
    );

    expect(find.byKey(const ValueKey('space-muted')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('channel-muted-$_generalId')),
      findsOneWidget,
    );
  });

  testWidgets('keeps a plain unread channel out of the mention badge', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      selectedChannelId: null,
      readState: ReadStateSnapshot(
        accountNotificationFlags: AccountNotificationFlags.useNewNotifications,
        settings: {
          _guildId: GuildNotificationSettings(
            spaceId: _guildId,
            flags: GuildNotificationFlags.unreadsOnlyMentions,
          ),
        },
      ),
    );

    // #general is unread with no mention: under "only mentions" it must render
    // as an ordinary read row, while #alerts keeps its mention pill.
    final general = tester.widget<Text>(find.text('general'));
    expect(general.style!.fontWeight, FontWeight.w400);
    expect(
      find.byKey(const ValueKey('channel-mention-$_alertsId')),
      findsOneWidget,
    );
  });

  testWidgets('hides muted channels when the guild asks for it', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      selectedChannelId: _alertsId,
      readState: ReadStateSnapshot(
        settings: {
          _guildId: GuildNotificationSettings(
            spaceId: _guildId,
            hideMutedChannels: true,
            channelOverrides: {
              _generalId: const ChannelNotificationOverride(
                channelId: _generalId,
                muted: true,
              ),
              _alertsId: const ChannelNotificationOverride(
                channelId: _alertsId,
                muted: true,
              ),
            },
          ),
        },
      ),
    );

    // #general is muted and neither selected nor mentioning: it goes. #alerts
    // is muted too but has a mention, so it stays.
    expect(find.byKey(const ValueKey('channel-$_generalId')), findsNothing);
    expect(find.byKey(const ValueKey('channel-$_alertsId')), findsOneWidget);
  });

  testWidgets('raises the space menu and reports the chosen row', (
    tester,
  ) async {
    final requests = <(NotificationMenuRequest, String?)>[];
    await _pumpSidebar(
      tester,
      readState: ReadStateSnapshot.empty,
      onNotificationRequest: (request, channel) =>
          requests.add((request, channel?.id)),
    );

    await tester.tap(find.byKey(const ValueKey('space-notification-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Suppress @everyone and @here'), findsOneWidget);
    expect(find.text('Mobile push notifications'), findsOneWidget);

    await tester.tap(find.text('Mute For 1 hour'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    final request = requests.single.$1 as MuteRequest;
    expect(request.muted, isTrue);
    expect(request.windowSeconds, 3600);
    expect(requests.single.$2, isNull);
  });

  testWidgets('raises the channel menu from a right click', (tester) async {
    final requests = <(NotificationMenuRequest, String?)>[];
    await _pumpSidebar(
      tester,
      readState: _mutedChannelSnapshot(),
      onNotificationRequest: (request, channel) =>
          requests.add((request, channel?.id)),
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('channel-$_generalId'))),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    // A muted channel offers exactly one mute row, and no guild-only rows.
    expect(find.text('Unmute'), findsOneWidget);
    expect(find.text('Mobile push notifications'), findsNothing);

    await tester.tap(find.text('Unmute'));
    await tester.pumpAndSettle();

    expect((requests.single.$1 as MuteRequest).muted, isFalse);
    expect(requests.single.$2, _generalId);
  });

  testWidgets('ticks the resolved notification level', (tester) async {
    await _pumpSidebar(
      tester,
      readState: ReadStateSnapshot(
        settings: {
          _guildId: GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.noMessages,
          ),
        },
      ),
      onNotificationRequest: (_, _) {},
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('channel-$_generalId'))),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    final checked = tester
        .widgetList<CheckedPopupMenuItem<NotificationMenuRequest>>(
          find.byType(CheckedPopupMenuItem<NotificationMenuRequest>),
        )
        .where((item) => item.checked)
        .toList();
    expect(checked, hasLength(1));
    expect(
      (checked.single.value! as NotificationLevelRequest).level,
      MessageNotificationLevel.noMessages,
    );
  });

  testWidgets('renders every uncategorised section it is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ChannelSidebar(
            space: _sectioned.spaces.single,
            channels: _sectioned.channels,
            selectedChannelId: _generalId,
            onSelectChannel: (_) {},
            sessionMode: SessionMode.demo,
            connectionStatus: RepositoryConnectionStatus.connected,
            categories: _sectioned.categoriesFor(_sectioned.spaces.single.id),
            currentMember: _sectioned.memberById(_sectioned.currentMemberId),
            memberOf: _sectioned.memberOrNull,
            channelOf: _sectioned.channelOrNull,
            collapsedCategoryIds: const {},
            onToggleCategory: (_) {},
            onNewDirectMessage: () {},
            readState: ReadStateSnapshot.empty,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Text channels'), findsOneWidget);
    expect(find.text('Active threads'), findsOneWidget);
    expect(find.text('Forums'), findsOneWidget);
    expect(find.text('Voice channels'), findsOneWidget);
    expect(find.byIcon(Icons.perm_media_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lists channels outside every category above them', (
    tester,
  ) async {
    final workspace = ChatWorkspace(
      spaces: _sectioned.spaces,
      categories: const [
        ChannelCategory(
          id: _forumId,
          spaceId: _guildId,
          name: 'Operations',
          position: 0,
        ),
      ],
      channels: const [
        ConversationChannel(
          id: _generalId,
          spaceId: _guildId,
          name: 'general',
          topic: '',
          kind: ChannelKind.text,
        ),
        ConversationChannel(
          id: _alertsId,
          spaceId: _guildId,
          name: 'alerts',
          topic: '',
          kind: ChannelKind.text,
          parentId: _forumId,
        ),
      ],
      members: _sectioned.members,
      messages: const [],
      currentMemberId: _memberId,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ChannelSidebar(
            space: workspace.spaces.single,
            channels: workspace.channels,
            selectedChannelId: _generalId,
            onSelectChannel: (_) {},
            sessionMode: SessionMode.demo,
            connectionStatus: RepositoryConnectionStatus.connected,
            categories: workspace.categoriesFor(workspace.spaces.single.id),
            currentMember: workspace.memberById(workspace.currentMemberId),
            memberOf: workspace.memberOrNull,
            channelOf: workspace.channelOrNull,
            collapsedCategoryIds: const {},
            onToggleCategory: (_) {},
            onNewDirectMessage: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('OPERATIONS'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-$_generalId')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-$_alertsId')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a compact window without overflowing', (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpSidebar(
      tester,
      readState: _mutedChannelSnapshot(),
      onNotificationRequest: (_, _) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('channel-sidebar')), findsOneWidget);
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required ReadStateSnapshot readState,
  String? selectedChannelId = _generalId,
  SidebarNotificationHandler? onNotificationRequest,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ChannelSidebar(
          space: _workspace.spaces.single,
          channels: _workspace.channels,
          selectedChannelId: selectedChannelId,
          onSelectChannel: (_) {},
          sessionMode: SessionMode.demo,
          connectionStatus: RepositoryConnectionStatus.connected,
          categories: _workspace.categoriesFor(_workspace.spaces.single.id),
          currentMember: _workspace.memberById(_workspace.currentMemberId),
          memberOf: _workspace.memberOrNull,
          channelOf: _workspace.channelOrNull,
          collapsedCategoryIds: const {},
          onToggleCategory: (_) {},
          onNewDirectMessage: () {},
          readState: readState,
          onNotificationRequest: onNotificationRequest,
        ),
      ),
    ),
  );
  await tester.pump();
}

ReadStateSnapshot _mutedChannelSnapshot() => ReadStateSnapshot(
  settings: {
    _guildId: GuildNotificationSettings(
      spaceId: _guildId,
      channelOverrides: {
        _generalId: const ChannelNotificationOverride(
          channelId: _generalId,
          muted: true,
        ),
      },
    ),
  },
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guildId,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: _generalId,
      spaceId: _guildId,
      name: 'general',
      topic: 'Core work',
      kind: ChannelKind.text,
      unread: true,
    ),
    ConversationChannel(
      id: _alertsId,
      spaceId: _guildId,
      name: 'alerts',
      topic: 'Signals',
      kind: ChannelKind.text,
      position: 1,
      unread: true,
      mentionCount: 3,
    ),
  ],
  members: const [
    Member(
      id: _memberId,
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: const [],
  currentMemberId: _memberId,
);

/// A guild with no categories at all, which is the branch that renders the
/// text, thread, forum and voice sections one after another.
final _sectioned = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guildId,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: _generalId,
      spaceId: _guildId,
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: _alertsId,
      spaceId: _guildId,
      name: 'planning',
      topic: '',
      kind: ChannelKind.text,
      parentId: _generalId,
      isThread: true,
    ),
    ConversationChannel(
      id: _forumId,
      spaceId: _guildId,
      name: 'ideas',
      topic: '',
      kind: ChannelKind.forum,
    ),
    ConversationChannel(
      id: _mediaId,
      spaceId: _guildId,
      name: 'gallery',
      topic: '',
      kind: ChannelKind.media,
    ),
    ConversationChannel(
      id: _voiceId,
      spaceId: _guildId,
      name: 'lounge',
      topic: '',
      kind: ChannelKind.voice,
    ),
  ],
  members: const [
    Member(
      id: _memberId,
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: const [],
  currentMemberId: _memberId,
);
