import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/friends_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/activity_views.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';
import 'support/flucord_icon_finder.dart';

// What the direct-messages sidebar looks like in direction B (FLUCORD-82):
// people on 40 px rows with a 28 px avatar, quiet at rest and full strength
// when open or unread.

final _surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

void main() {
  testWidgets('the header is a search field that is never cut off', (
    tester,
  ) async {
    await loadAppFont(tester);
    var opened = 0;
    await _pumpSidebar(tester, onNewDirectMessage: () => opened++);

    const hint = 'Find or start a conversation';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(hint));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
      reason: 'the whole hint is drawn, not an ellipsis',
    );
    final field = find.byKey(const ValueKey('new-direct-message'));
    expect(tester.getSize(field).height, 28);

    await tester.tap(field);
    expect(opened, 1);
  });

  testWidgets('Friends sits above the DMs and is filled while open', (
    tester,
  ) async {
    final friends = FriendsController(() => null);
    addTearDown(friends.dispose);
    await _pumpSidebar(tester, friends: friends);

    final row = find.byKey(const ValueKey('toggle-friends'));
    expect(
      find.descendant(of: row, matching: find.text('Friends')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: findFlucordIcon(FlucordIcons.friends)),
      findsOneWidget,
    );
    expect(
      tester.getRect(row).bottom,
      lessThan(tester.getRect(find.text('Direct messages')).top),
    );

    await tester.tap(row);
    await tester.pump();

    expect(friends.isPanelOpen, isTrue);
    // The page opens in the canvas; the DMs stay listed here.
    expect(_row('dm-bo'), findsOneWidget);
    final fill = tester
        .widget<Material>(
          find.descendant(of: row, matching: find.byType(Material)).first,
        )
        .color;
    expect(fill, _surfaces.text.withValues(alpha: 0.06));
  });

  testWidgets('a DM row is 40 high with a 28 px avatar and a status dot', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    expect(tester.getSize(_row('dm-bo')).height, 40);
    final avatar = find.descendant(
      of: _row('dm-bo'),
      matching: find.byType(MemberAvatar),
    );
    expect(tester.getSize(avatar), const Size.square(28));
    expect(
      find.descendant(
        of: avatar,
        matching: find.byKey(const ValueKey('member-presence-bo')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a DM row says what the person is doing under the name', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final line = find.descendant(
      of: _row('dm-jack'),
      matching: find.byType(ActivitySummaryLine),
    );
    expect(
      find.descendant(of: line, matching: find.text('Dota 2')),
      findsOneWidget,
    );
    expect(
      tester.getRect(line).top,
      greaterThanOrEqualTo(tester.getRect(find.text('Jack')).bottom),
    );
    expect(
      find.descendant(
        of: _row('dm-bo'),
        matching: find.byType(ActivitySummaryLine),
      ),
      findsNothing,
    );
  });

  testWidgets('a DM at rest names the person in secondary text', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final name = _textStyle(tester, 'Bo');
    expect(name.color, _surfaces.muted);
    expect(name.fontWeight, FontWeight.w400);
    expect(_fillOf(tester, 'dm-bo'), Colors.transparent);
  });

  testWidgets('an unread DM names the person at full strength', (tester) async {
    await _pumpSidebar(tester);

    final name = _textStyle(tester, 'Ann');
    expect(name.color, _surfaces.text);
    expect(name.fontWeight, FontWeight.w500);
  });

  testWidgets('the open DM has a soft fill with the control radius', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final name = _textStyle(tester, 'Jack');
    expect(name.color, _surfaces.text);
    expect(name.fontWeight, FontWeight.w500);
    final surface = _surfaceOf(tester, 'dm-jack');
    expect(surface.color, _surfaces.text.withValues(alpha: 0.06));
    expect(surface.borderRadius, FlucordRadius.control);
  });

  testWidgets('a message request is a person row with icon answers', (
    tester,
  ) async {
    await _pumpSidebar(tester);

    final folder = find.byKey(const ValueKey('message-requests-folder'));
    expect(
      find.descendant(
        of: folder,
        matching: findFlucordIcon(FlucordIcons.inbox),
      ),
      findsOneWidget,
    );
    await tester.tap(folder);
    await tester.pump();

    final request = find.byKey(const ValueKey('request-dm-cy'));
    expect(tester.getSize(request).height, 40);
    expect(
      tester.getSize(
        find.descendant(of: request, matching: find.byType(MemberAvatar)),
      ),
      const Size.square(28),
    );
    for (final (key, icon) in [
      ('accept-request-dm-cy', FlucordIcons.check),
      ('decline-request-dm-cy', FlucordIcons.clear),
    ]) {
      final button = find.byKey(ValueKey(key));
      expect(tester.getSize(button), const Size.square(28));
      expect(
        find.descendant(of: button, matching: findFlucordIcon(icon)),
        findsOneWidget,
      );
    }
    for (final part in [folder, request]) {
      expect(
        find.descendant(of: part, matching: find.byType(Icon)),
        findsNothing,
      );
    }
  });

  testWidgets('the conversations come back when the last request goes', (
    tester,
  ) async {
    await _pumpSidebar(tester);
    await tester.tap(find.byKey(const ValueKey('message-requests-folder')));
    await tester.pump();
    expect(_row('dm-jack'), findsNothing);

    await _pumpSidebar(
      tester,
      workspace: _workspace.copyWith(
        channels: [
          for (final channel in _workspace.channels)
            if (!channel.isMessageRequest) channel,
        ],
      ),
    );

    expect(_row('dm-jack'), findsOneWidget);
  });

  testWidgets('the open DM stays in view when a message moves it up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Thirty conversations, the oldest last; the open one is that oldest.
    final crowded = _workspace.copyWith(
      channels: [
        for (var index = 30; index > 0; index--)
          _dm(
            'p$index',
          ).copyWith(lastMessageId: '${500000000000000000 + index}'),
      ],
    );
    await _pumpSidebar(tester, workspace: crowded, selectedChannelId: 'dm-p1');
    await tester.ensureVisible(_row('dm-p1'));
    await tester.pumpAndSettle();
    expect(_isInView(tester, 'dm-p30'), isFalse);

    await _pumpSidebar(
      tester,
      workspace: crowded.recordLatestMessage('dm-p1', '600000000000000000'),
      selectedChannelId: 'dm-p1',
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(_row('dm-p1')).dy,
      lessThan(tester.getTopLeft(_row('dm-p30')).dy),
      reason: 'the new message moved the open DM to the top',
    );
    expect(_isInView(tester, 'dm-p1'), isTrue);
  });
}

final _sidebarList = find.descendant(
  of: find.descendant(
    of: find.byKey(const ValueKey('channel-sidebar')),
    matching: find.byType(ListView),
  ),
  matching: find.byType(Scrollable),
);

/// Whether the row of [channelId] is built and inside the sidebar's list.
bool _isInView(WidgetTester tester, String channelId) {
  if (_row(channelId).evaluate().isEmpty) return false;
  final list = tester.getRect(_sidebarList);
  final row = tester.getRect(_row(channelId));
  return row.top >= list.top && row.bottom <= list.bottom;
}

Finder _row(String channelId) => find.byKey(ValueKey('channel-$channelId'));

TextStyle _textStyle(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

Material _surfaceOf(WidgetTester tester, String channelId) =>
    tester.widget<Material>(
      find.ancestor(of: _row(channelId), matching: find.byType(Material)).first,
    );

Color? _fillOf(WidgetTester tester, String channelId) =>
    _surfaceOf(tester, channelId).color;

Future<void> _pumpSidebar(
  WidgetTester tester, {
  ChatWorkspace? workspace,
  FriendsController? friends,
  VoidCallback? onNewDirectMessage,
  String selectedChannelId = 'dm-jack',
}) async {
  final shown = workspace ?? _workspace;
  Widget sidebar() => ChannelSidebar(
    space: shown.spaceById(CommunitySpace.directMessagesId),
    channels: shown.channelsFor(CommunitySpace.directMessagesId),
    selectedChannelId: selectedChannelId,
    onSelectChannel: (_) {},
    sessionMode: SessionMode.discord,
    connectionStatus: RepositoryConnectionStatus.connected,
    categories: const [],
    currentMember: shown.memberById(shown.currentMemberId),
    memberOf: shown.memberOrNull,
    channelOf: shown.channelOrNull,
    collapsedCategoryIds: const {},
    onToggleCategory: (_) {},
    onNewDirectMessage: onNewDirectMessage ?? () {},
    friends: friends,
    onAcceptMessageRequest: (_) {},
    onDeclineMessageRequest: (_) {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (friends == null)
              sidebar()
            else
              ListenableBuilder(
                listenable: friends,
                builder: (_, _) => sidebar(),
              ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
}

ConversationChannel _dm(
  String person, {
  bool unread = false,
  bool request = false,
}) => ConversationChannel(
  id: 'dm-$person',
  spaceId: CommunitySpace.directMessagesId,
  name: '${person[0].toUpperCase()}${person.substring(1)}',
  topic: '',
  kind: ChannelKind.text,
  recipientIds: [person],
  unread: unread,
  isMessageRequest: request,
);

Member _person(
  String id,
  Presence presence, {
  List<UserActivity> activities = const [],
}) => Member(
  id: id,
  displayName: '${id[0].toUpperCase()}${id.substring(1)}',
  initials: id[0].toUpperCase(),
  role: 'Direct message',
  presence: presence,
  colorValue: 0xff59636a,
  spaceIds: const {CommunitySpace.directMessagesId},
  presenceDetail: UserPresence(status: presence, activities: activities),
);

final _workspace = ChatWorkspace(
  spaces: const [CommunitySpace.directMessages()],
  channels: [
    _dm('jack'),
    _dm('ann', unread: true),
    _dm('bo'),
    _dm('cy', request: true),
  ],
  members: [
    const Member(
      id: 'me',
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
    _person(
      'jack',
      Presence.online,
      activities: const [UserActivity(name: 'Dota 2')],
    ),
    _person('ann', Presence.idle),
    _person('bo', Presence.offline),
    _person('cy', Presence.online),
  ],
  messages: const [],
  currentMemberId: 'me',
);
