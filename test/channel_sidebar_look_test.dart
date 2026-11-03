import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flucord_icon_finder.dart';

// What the channel list looks like in direction B (FLUCORD-78): one row
// height, a soft selected fill, unread by text strength and an edge marker,
// and a green ring on whoever is speaking.

final _surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

void main() {
  testWidgets('the server header is 48 high with the name as a heading', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final menu = find.byKey(const ValueKey('space-menu'));
    expect(tester.getSize(menu).height, 48);

    final name = _textStyle(tester, 'The Forge');
    expect(name.fontSize, FlucordTextRole.heading.size);
    expect(name.fontWeight, FontWeight.w500);
    expect(
      find.descendant(
        of: menu,
        matching: findFlucordIcon(FlucordIcons.chevronDown),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a category label is a caption with 16 above and 4 below', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final label = find.text('OPERATIONS');
    final style = _textStyle(tester, 'OPERATIONS');
    expect(style.fontSize, FlucordTextRole.caption.size);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.color, _surfaces.captionText);

    final header = tester.getRect(find.byKey(const ValueKey('space-menu')));
    final labelRect = tester.getRect(label);
    expect(labelRect.top - header.bottom, 16);
    expect(labelRect.height, FlucordTextRole.caption.lineHeight);

    final firstRow = tester.getRect(_row('general'));
    expect(firstRow.top - labelRect.bottom, 4);
  });

  testWidgets('every channel row is 30 high with a 16 px icon', (tester) async {
    await _pumpSidebar(tester);

    for (final id in const ['general', 'alerts', 'random', 'the-lodge']) {
      expect(tester.getSize(_row(id)).height, 30, reason: id);
    }
    final hash = find.descendant(
      of: _row('random'),
      matching: findFlucordIcon(FlucordIcons.textChannel),
    );
    expect(tester.getSize(hash), const Size.square(16));
    expect(
      find.descendant(
        of: _row('the-lodge'),
        matching: findFlucordIcon(FlucordIcons.voiceChannel),
      ),
      findsOneWidget,
    );
    expect(_textStyle(tester, 'random').fontSize, FlucordTextRole.label.size);
  });

  testWidgets('a channel at rest is secondary text on no fill', (tester) async {
    await _pumpSidebar(tester);

    final rest = _textStyle(tester, 'the-den');
    expect(rest.color, _surfaces.muted);
    expect(rest.fontWeight, FontWeight.w400);
    expect(_fillOf(tester, 'the-den'), Colors.transparent);
    expect(find.byKey(const ValueKey('channel-unread-the-den')), findsNothing);
  });

  testWidgets('the selected channel has a soft fill and a full name', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final selected = _textStyle(tester, 'general');
    expect(selected.color, _surfaces.text);
    expect(selected.fontWeight, FontWeight.w500);
    expect(_fillOf(tester, 'general'), _surfaces.text.withValues(alpha: 0.06));
  });

  testWidgets('an unread channel is full strength with an edge marker', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final unread = _textStyle(tester, 'random');
    expect(unread.color, _surfaces.text);
    expect(unread.fontWeight, FontWeight.w500);
    expect(_fillOf(tester, 'random'), Colors.transparent);

    final marker = tester.getRect(
      find.byKey(const ValueKey('channel-unread-random')),
    );
    final sidebar = tester.getRect(
      find.byKey(const ValueKey('channel-sidebar')),
    );
    final row = tester.getRect(_row('random'));
    expect(marker.size, const Size(4, 8));
    expect(marker.left, sidebar.left);
    expect(marker.center.dy, row.center.dy);
  });

  testWidgets('a voice participant sits under the channel, name aligned', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final seat = find.byKey(const ValueKey('voice-seat-the-lodge-bot-1'));
    final channelName = tester.getRect(find.text('The Lodge'));
    final avatar = tester.getRect(
      find.byKey(const ValueKey('voice-seat-avatar-bot-1')),
    );
    expect(
      tester.getRect(seat).top,
      greaterThanOrEqualTo(tester.getRect(_row('the-lodge')).bottom),
    );
    expect(avatar.size, const Size.square(20));
    // Indented under the channel: the avatar starts where its name does.
    expect(avatar.left, channelName.left);
    expect(
      _textStyle(tester, 'Flucord Bot').fontSize,
      FlucordTextRole.label.size,
    );
  });

  testWidgets('the participant who is speaking has a green ring', (
    tester,
  ) async {
    await _pumpSidebar(tester);
    expect(_ringOf(tester, 'bot-1'), isNull);

    await _pumpSidebar(tester, speakingUserIds: const {'bot-1'});
    final ring = _ringOf(tester, 'bot-1')!;
    expect(ring.width, 2);
    expect(ring.color, _surfaces.success);
    final ringBox = tester.getRect(
      find.byKey(const ValueKey('voice-seat-ring-bot-1')),
    );
    final avatar = tester.getRect(
      find.byKey(const ValueKey('voice-seat-avatar-bot-1')),
    );
    // Around the avatar, not over it.
    expect(ringBox.center, avatar.center);
    expect(ringBox.width, avatar.width + 2 * 2);
  });
}

Finder _row(String channelId) => find.byKey(ValueKey('channel-$channelId'));

TextStyle _textStyle(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

/// The fill a row's surface paints behind it.
Color? _fillOf(WidgetTester tester, String channelId) => tester
    .widget<Material>(
      find.ancestor(of: _row(channelId), matching: find.byType(Material)).first,
    )
    .color;

/// The ring side drawn around a seat's avatar, or null when it draws none.
BorderSide? _ringOf(WidgetTester tester, String userId) {
  final ring = find.byKey(ValueKey('voice-seat-ring-$userId'));
  if (ring.evaluate().isEmpty) return null;
  final box = tester.widget<Container>(ring);
  final border = (box.decoration! as BoxDecoration).border! as Border;
  return border.top;
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  Set<String> speakingUserIds = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChannelSidebar(
              space: _workspace.spaces.single,
              channels: _workspace.channels,
              selectedChannelId: 'general',
              onSelectChannel: (_) {},
              sessionMode: SessionMode.demo,
              connectionStatus: RepositoryConnectionStatus.connected,
              categories: _workspace.categoriesFor('guild-1'),
              currentMember: _workspace.memberById(_workspace.currentMemberId),
              memberOf: _workspace.memberOrNull,
              channelOf: _workspace.channelOrNull,
              collapsedCategoryIds: const {},
              onToggleCategory: (_) {},
              onNewDirectMessage: () {},
              onOpenServerSettings: () {},
              seatedByChannel: const {
                'the-lodge': [_seat],
              },
              speakingUserIds: speakingUserIds,
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
}

const _seat = VoiceParticipantStateEvent(
  userId: 'bot-1',
  channelId: 'the-lodge',
  guildId: 'guild-1',
  selfMuted: false,
  selfDeafened: false,
  serverMuted: false,
  serverDeafened: false,
  isStreaming: false,
  isVideoEnabled: false,
);

ConversationChannel _channel(
  String id,
  int position, {
  ChannelKind kind = ChannelKind.text,
  bool unread = false,
}) => ConversationChannel(
  id: id,
  spaceId: 'guild-1',
  name: id == 'the-lodge' ? 'The Lodge' : id,
  topic: '',
  kind: kind,
  position: position,
  parentId: 'category-1',
  unread: unread,
);

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
  channels: [
    _channel('general', 1),
    _channel('alerts', 2, unread: true),
    _channel('random', 3, unread: true),
    _channel('the-den', 4),
    _channel('the-lodge', 5, kind: ChannelKind.voice),
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
    Member(
      id: 'me',
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: const [],
  currentMemberId: 'me',
);
