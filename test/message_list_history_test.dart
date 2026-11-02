import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flucord/src/presentation/widgets/user_settings_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/fake_user_settings_repository.dart';

void main() {
  testWidgets('shows load, progress, and retry history boundaries', (
    tester,
  ) async {
    final messages = List.generate(4, (index) => _message(index + 10));
    var requests = 0;

    await tester.pumpWidget(_host(messages, onLoadOlder: () => requests++));
    await tester.pump();
    expect(find.byKey(const ValueKey('load-older-messages')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('load-older-messages')));
    expect(requests, 1);

    await tester.pumpWidget(
      _host(messages, isLoadingOlder: true, onLoadOlder: () => requests++),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _host(
        messages,
        olderLoadError: StateError('offline'),
        onLoadOlder: () => requests++,
      ),
    );
    expect(find.text('Older messages unavailable'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-older-messages')));
    expect(requests, 2);
  });

  testWidgets('preserves the visible message when history is prepended', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final current = List.generate(30, (index) => _message(index + 10));

    await tester.pumpWidget(_host(current));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    final anchor = find.byKey(const ValueKey('message-m020'));
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    await tester.pumpWidget(
      _host([...List.generate(10, _message), ...current]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-m020')), findsOneWidget);
    final after = tester.getTopLeft(anchor).dy;
    expect(after, closeTo(before, 1));
  });

  testWidgets('positions the timeline at the first unread message', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messages = List.generate(50, _message);
    final channel = _channel.copyWith(firstUnreadMessageId: 'm025');

    await tester.pumpWidget(_host(messages, channel: channel));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('unread-message-boundary')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('New messages'), findsOneWidget);
    final unreadMessage = find.byKey(const ValueKey('message-m025'));
    expect(unreadMessage, findsOneWidget);
    expect(tester.getTopLeft(unreadMessage).dy, inInclusiveRange(60, 250));
    expect(find.byKey(const ValueKey('jump-to-unread')), findsNothing);
    semantics.dispose();
  });

  testWidgets('hides the unread boundary while filtering messages', (
    tester,
  ) async {
    final channel = _channel.copyWith(firstUnreadMessageId: 'm010');
    await tester.pumpWidget(
      _host(List.generate(20, _message), channel: channel, query: 'Message 15'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-message-boundary')), findsNothing);
    expect(find.textContaining('Message 15'), findsOneWidget);
  });

  testWidgets('opens at the newest message when nothing is unread', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(List.generate(60, _unevenMessage)));
    await tester.pumpAndSettle();

    final newest = find.byKey(const ValueKey('message-m059'));
    expect(newest, findsOneWidget);
    expect(tester.getBottomLeft(newest).dy, lessThanOrEqualTo(500));
  });

  testWidgets('opens on the unread message among unevenly tall ones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final channel = _channel.copyWith(firstUnreadMessageId: 'm040');

    await tester.pumpWidget(
      _host(List.generate(60, _unevenMessage), channel: channel),
    );
    await tester.pumpAndSettle();

    final unread = find.byKey(const ValueKey('message-m040'));
    expect(unread, findsOneWidget);
    expect(tester.getTopLeft(unread).dy, inInclusiveRange(0, 400));
  });

  testWidgets('offers the way back to the newest message and takes it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final channel = _channel.copyWith(firstUnreadMessageId: 'm020');

    await tester.pumpWidget(
      _host(List.generate(60, _unevenMessage), channel: channel),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jump-to-present')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-m059')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('jump-to-present')));
    await tester.pumpAndSettle();

    final newest = find.byKey(const ValueKey('message-m059'));
    expect(newest, findsOneWidget);
    expect(tester.getBottomLeft(newest).dy, lessThanOrEqualTo(500));
    expect(find.byKey(const ValueKey('jump-to-present')), findsNothing);
  });

  testWidgets('a channel already at its newest offers no way back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(List.generate(60, _unevenMessage)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jump-to-present')), findsNothing);
  });

  testWidgets('positions the timeline at an explicit inbox message', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(List.generate(50, _message), targetMessageId: 'm012'),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('message-m012'));
    expect(target, findsOneWidget);
    expect(tester.getTopLeft(target).dy, inInclusiveRange(60, 250));
  });

  group('a channel opened on an unread boundary', () {
    final boundary = _channel.copyWith(firstUnreadMessageId: 'm100');
    final held = List.generate(150, _message);
    final arrived = [...held, _message(150), _message(151)];

    Future<void> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(held, channel: boundary));
      await tester.pumpAndSettle();
    }

    testWidgets('holds still for a reader scrolled up when messages arrive', (
      tester,
    ) async {
      await open(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('message-m100'));
      final top = tester.getTopLeft(row).dy;

      await tester.pumpWidget(_host(arrived, channel: boundary));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(row).dy, top);
    });

    testWidgets('follows new messages for a reader at the end', (tester) async {
      await open(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -9000));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(arrived, channel: boundary));
      await tester.pumpAndSettle();

      final newest = find.byKey(const ValueKey('message-m151'));
      expect(newest, findsOneWidget);
      expect(tester.getBottomLeft(newest).dy, lessThanOrEqualTo(500));
    });

    testWidgets('follows when the boundary sits next to the end', (
      tester,
    ) async {
      final nearEnd = _channel.copyWith(firstUnreadMessageId: 'm148');
      await tester.binding.setSurfaceSize(const Size(700, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(held, channel: nearEnd));
      await tester.pumpAndSettle();

      final messages = [...held];
      for (var index = 150; index < 170; index++) {
        messages.add(_message(index));
        await tester.pumpWidget(_host(List.of(messages), channel: nearEnd));
        await tester.pumpAndSettle();

        final newest = find.byKey(ValueKey('message-${_message(index).id}'));
        expect(newest, findsOneWidget);
        expect(tester.getBottomLeft(newest).dy, lessThanOrEqualTo(500));
      }
    });

    testWidgets('keeps the rows above it when the boundary is cleared', (
      tester,
    ) async {
      await open(tester);
      final row = find.byKey(const ValueKey('message-m099'));
      final top = tester.getTopLeft(row).dy;

      await tester.pumpWidget(_host(held, channel: _channel));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(row).dy, top);
    });
  });

  testWidgets('a boundary that appears later is no jump', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final held = List.generate(150, _message);
    await tester.pumpWidget(_host(held));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('message-m135'));
    final top = tester.getTopLeft(row).dy;

    await tester.pumpWidget(
      _host([
        ...held,
        _message(150),
      ], channel: _channel.copyWith(firstUnreadMessageId: 'm150')),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(row).dy, top);
  });

  testWidgets('a reader at the end stays there when the newest is deleted', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messages = List.generate(60, _message);
    await tester.pumpWidget(_host(messages));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(messages.sublist(0, 59)));
    await tester.pumpAndSettle();

    final newest = find.byKey(const ValueKey('message-m058'));
    expect(newest, findsOneWidget);
    expect(tester.getBottomLeft(newest).dy, lessThanOrEqualTo(500));
    expect(find.byKey(const ValueKey('jump-to-present')), findsNothing);
  });

  group('dates', () {
    testWidgets('a day divider appears when an arriving message starts a day', (
      tester,
    ) async {
      final first = _sentAt('m001', DateTime(2026, 3, 1, 23, 58));
      await tester.pumpWidget(_host([first]));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host([first, _sentAt('m002', DateTime(2026, 3, 2, 0, 3))]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Monday, March 2, 2026'), findsOneWidget);
    });

    testWidgets('a divider sits between messages on different local days', (
      tester,
    ) async {
      // Sent minutes apart, and given in UTC the way a wire time can be: the
      // day that counts is the one on the reader's own calendar.
      await tester.pumpWidget(
        _host([
          _sentAt('m001', DateTime(2026, 3, 1, 23, 58).toUtc()),
          _sentAt('m002', DateTime(2026, 3, 2, 0, 3).toUtc()),
        ]),
      );
      await tester.pumpAndSettle();

      final divider = find.text('Monday, March 2, 2026');
      expect(divider, findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('message-m001'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(divider).dy),
      );
      expect(
        tester.getBottomLeft(divider).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const ValueKey('message-m002'))).dy,
        ),
      );
    });

    testWidgets('messages on one day have no divider between them', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          _sentAt('m001', DateTime(2026, 3, 2, 9, 0)),
          _sentAt('m002', DateTime(2026, 3, 2, 21, 0)),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('March 2, 2026'), findsNothing);
    });

    testWidgets('one author does not group across midnight', (tester) async {
      await tester.pumpWidget(
        _host([
          _sentAt('m001', DateTime(2026, 3, 1, 23, 58)),
          _sentAt('m002', DateTime(2026, 3, 2, 0, 3)),
        ]),
      );
      await tester.pumpAndSettle();

      // Each row that opens a group carries the author's name.
      expect(find.text('Flucord'), findsNWidgets(2));
    });

    testWidgets('one author still groups within a day', (tester) async {
      await tester.pumpWidget(
        _host([
          _sentAt('m001', DateTime(2026, 3, 2, 9, 0)),
          _sentAt('m002', DateTime(2026, 3, 2, 9, 5)),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flucord'), findsOneWidget);
    });

    group('hovering a timestamp shows the full date', () {
      final message = DateTime(2026, 3, 1, 21, 4);

      testWidgets('in the 12-hour cycle the account chose', (tester) async {
        final settings = await _settings(TimestampHourCycle.hour12);
        await tester.pumpWidget(
          _host([_sentAt('m001', message)], settings: settings),
        );
        await tester.pumpAndSettle();

        await _hover(tester, find.text('9:04 PM'));

        expect(find.text('Sunday, March 1, 2026 at 9:04 PM'), findsOneWidget);
      });

      testWidgets('in the 24-hour cycle the account chose', (tester) async {
        final settings = await _settings(TimestampHourCycle.hour23);
        await tester.pumpWidget(
          _host([_sentAt('m001', message)], settings: settings),
        );
        await tester.pumpAndSettle();

        await _hover(tester, find.text('21:04'));

        expect(find.text('Sunday, March 1, 2026 at 21:04'), findsOneWidget);
      });

      testWidgets('on a grouped row', (tester) async {
        final settings = await _settings(TimestampHourCycle.hour12);
        await tester.pumpWidget(
          _host([
            _sentAt('m001', message),
            _sentAt('m002', message.add(const Duration(minutes: 2))),
          ], settings: settings),
        );
        await tester.pumpAndSettle();

        await _hover(tester, find.text('9:06 PM'));

        expect(find.text('Sunday, March 1, 2026 at 9:06 PM'), findsOneWidget);
      });

      testWidgets('on a system message', (tester) async {
        final settings = await _settings(TimestampHourCycle.hour12);
        await tester.pumpWidget(
          _host([
            _sentAt('m001', message, type: DiscordMessageType.userJoin),
          ], settings: settings),
        );
        await tester.pumpAndSettle();

        await _hover(tester, find.text('9:04 PM'));

        expect(find.text('Sunday, March 1, 2026 at 9:04 PM'), findsOneWidget);
      });
    });
  });
}

/// Rests a mouse on [target] for as long as a tooltip waits before it opens.
Future<void> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<UserSettingsController> _settings(TimestampHourCycle cycle) async {
  final controller = UserSettingsController(
    () => FakeUserSettingsRepository(
      UserSettings(
        appearance: AppearancePreferences(timestampHourCycle: cycle),
      ),
    ),
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Widget _host(
  List<ChatMessage> messages, {
  bool isLoadingOlder = false,
  Object? olderLoadError,
  VoidCallback? onLoadOlder,
  ConversationChannel channel = _channel,
  String query = '',
  String? targetMessageId,
  UserSettingsController? settings,
}) {
  final list = MessageList(
    workspace: ChatWorkspace(
      spaces: const [_space],
      channels: [channel],
      members: const [_member],
      messages: messages,
      currentMemberId: 'bot-1',
    ),
    channel: channel,
    query: query,
    targetMessageId: targetMessageId,
    onReply: (_) {},
    onEdit: (_, _) async => true,
    onDelete: (_) async {},
    onToggleReaction: (_, _) async {},
    onLoadReactionUsers: (_, _, _, _) async =>
        const ReactionUsersPage(users: [], hasMore: false),
    onAddReaction: (_, _) async {},
    onCreateThread: (_, _, _) async => true,
    onTogglePin: (_) async {},
    onEndPoll: (_) async => true,
    onForward: (_, _) async => true,
    onToggleSuppressEmbeds: (_) async => true,
    canLoadOlder: true,
    isLoadingOlder: isLoadingOlder,
    olderLoadError: olderLoadError,
    onLoadOlder: onLoadOlder ?? () {},
    externalLinkLauncher: const _TestLinkLauncher(),
    onSelectChannel: (_) {},
  );
  return MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: SizedBox(
        width: 700,
        height: 500,
        child: settings == null
            ? list
            : UserSettingsScope(controller: settings, child: list),
      ),
    ),
  );
}

ChatMessage _message(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(3, '0')}',
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: 'Message $index with enough content to keep row height stable.',
  sentAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
);

ChatMessage _sentAt(
  String id,
  DateTime sentAt, {
  DiscordMessageType type = DiscordMessageType.defaultMessage,
}) => ChatMessage(
  id: id,
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: 'Sent as $id',
  sentAt: sentAt,
  type: type,
);

/// Messages whose heights differ by an order of magnitude, which is what a
/// real channel looks like and what a position estimate cannot survive.
ChatMessage _unevenMessage(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(3, '0')}',
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: index.isEven
      ? 'ok'
      : List.filled(
          index % 7 + 1,
          'A long paragraph of content that wraps across several lines.',
        ).join(String.fromCharCode(10)),
  sentAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
);

const _space = CommunitySpace(
  id: 'space-1',
  name: 'Forge',
  monogram: 'FO',
  colorValue: 0xff456b5a,
);

const _channel = ConversationChannel(
  id: 'channel-1',
  spaceId: 'space-1',
  name: 'general',
  topic: 'History',
  kind: ChannelKind.text,
);

const _member = Member(
  id: 'bot-1',
  displayName: 'Flucord',
  initials: 'FL',
  role: 'Bot',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
