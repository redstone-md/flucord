import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/presentation/widgets/message_embed_view.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/presentation/widgets/message_reaction_strip.dart';
import 'package:flucord/src/presentation/widgets/message_timestamp.dart';
import 'package:flucord/src/presentation/widgets/user_settings_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  group('MessageTimestamp', () {
    test('renders the 24-hour clock for automatic and 24-hour', () {
      final value = DateTime(2026, 7, 23, 21, 4);

      expect(MessageTimestamp.format(value, TimestampHourCycle.auto), '21:04');
      expect(
        MessageTimestamp.format(value, TimestampHourCycle.hour23),
        '21:04',
      );
    });

    test('renders the 12-hour clock across noon and midnight', () {
      expect(
        MessageTimestamp.format(
          DateTime(2026, 7, 23, 21, 4),
          TimestampHourCycle.hour12,
        ),
        '9:04 PM',
      );
      expect(
        MessageTimestamp.format(
          DateTime(2026, 7, 23, 0, 9),
          TimestampHourCycle.hour12,
        ),
        '12:09 AM',
      );
      expect(
        MessageTimestamp.format(
          DateTime(2026, 7, 23, 12, 0),
          TimestampHourCycle.hour12,
        ),
        '12:00 PM',
      );
    });
  });

  testWidgets('renders everything when no session publishes settings', (
    tester,
  ) async {
    await _pumpMessage(tester, controller: null);

    expect(find.text('03:47'), findsOneWidget);
    expect(find.byType(MessageReactionStrip), findsOneWidget);
    expect(find.byType(MessageEmbedView), findsOneWidget);
  });

  testWidgets('honours the account display settings on a message', (
    tester,
  ) async {
    final controller = await _controller(
      const UserSettings(
        appearance: AppearancePreferences(
          timestampHourCycle: TimestampHourCycle.hour12,
        ),
        messageDisplay: MessageDisplayPreferences(
          renderEmbeds: false,
          renderReactions: false,
          inlineAttachmentMedia: false,
        ),
      ),
    );
    await _pumpMessage(tester, controller: controller);

    expect(find.text('3:47 AM'), findsOneWidget);
    expect(find.byType(MessageReactionStrip), findsNothing);
    expect(find.byType(MessageEmbedView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps an animated emoji on its first frame when told to', (
    tester,
  ) async {
    final controller = await _controller(
      const UserSettings(
        messageDisplay: MessageDisplayPreferences(animateEmoji: false),
      ),
    );
    await _pumpMessage(tester, controller: controller, message: _emojiMessage);

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('discord-emoji-333333')),
        matching: find.byType(Image),
      ),
    );
    // The webp form is the animated emoji's first frame.
    expect((image.image as NetworkImage).url, contains('.webp'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plays an animated emoji when the account allows it', (
    tester,
  ) async {
    final controller = await _controller(
      const UserSettings(
        messageDisplay: MessageDisplayPreferences(animateEmoji: true),
      ),
    );
    await _pumpMessage(tester, controller: controller, message: _emojiMessage);

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('discord-emoji-333333')),
        matching: find.byType(Image),
      ),
    );
    expect((image.image as NetworkImage).url, contains('.gif'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a GIF embed on its first frame when autoplay is off', (
    tester,
  ) async {
    final controller = await _controller(
      const UserSettings(
        messageDisplay: MessageDisplayPreferences(gifAutoPlay: false),
      ),
    );
    await _pumpMessage(tester, controller: controller, message: _gifMessage);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('embed-image')),
    );
    expect((image.image as NetworkImage).url, endsWith('format=png'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plays a GIF embed when autoplay is on', (tester) async {
    final controller = await _controller(
      const UserSettings(
        messageDisplay: MessageDisplayPreferences(gifAutoPlay: true),
      ),
    );
    await _pumpMessage(tester, controller: controller, message: _gifMessage);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('embed-image')),
    );
    expect((image.image as NetworkImage).url, isNot(contains('format=png')));
    expect(tester.takeException(), isNull);
  });
}

Future<UserSettingsController> _controller(UserSettings settings) async {
  final controller = UserSettingsController(() => _Repository(settings));
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Future<void> _pumpMessage(
  WidgetTester tester, {
  required UserSettingsController? controller,
  ChatMessage? message,
}) async {
  await tester.binding.setSurfaceSize(const Size(820, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final item = MessageItem(
    message: message ?? _message,
    member: _member,
    workspace: _workspace,
    grouped: false,
    isCurrentUser: false,
    onReply: (_) {},
    onEdit: (_, _) async => true,
    onDelete: (_) async {},
    onToggleReaction: (_, _) async {},
    onLoadReactionUsers: (_, _, _, _) async =>
        const ReactionUsersPage(users: [_member], hasMore: false),
    onAddReaction: (_, _) async {},
    onCreateThread: (_, _, _) async => true,
    onTogglePin: (_) async {},
    onEndPoll: (_) async => true,
    onForward: (_, _) async => true,
    onToggleSuppressEmbeds: (_) async => true,
    linkLauncher: const _TestLinkLauncher(),
    onSelectChannel: (_) {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: controller == null
            ? item
            : UserSettingsScope(controller: controller, child: item),
      ),
    ),
  );
  await tester.pump();
}

final class _Repository implements UserSettingsRepository {
  _Repository(this._settings);

  final UserSettings _settings;

  @override
  Stream<UserSettings> get updates => const Stream.empty();

  @override
  UserSettings? get current => null;

  @override
  bool get isLoaded => false;

  @override
  Object? get lastWriteError => null;

  @override
  Future<UserSettings> load() async => _settings;

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {}

  @override
  Future<void> flush() async {}
}

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}

const _member = Member(
  id: 'member-1',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Design',
  presence: Presence.online,
  colorValue: 0xff665f82,
);

final _message = ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Settings should reach the timeline.',
  sentAt: DateTime(2026, 7, 23, 3, 47),
  reactions: const [MessageReaction(emojiName: '🚀', count: 2)],
  embeds: [
    MessageEmbed(
      type: 'rich',
      title: 'Deploy complete',
      description: 'Windows package is ready.',
      image: const MessageEmbedMedia(
        url: 'https://invalid.example/image.png',
        width: 1200,
        height: 630,
      ),
    ),
  ],
);

/// A message whose body carries a custom emoji the sender's client reported
/// as animated, the form the timeline is asked to draw.
final _emojiMessage = ChatMessage(
  id: 'message-2',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'party <a:duck:333333> time',
  sentAt: DateTime(2026, 7, 23, 3, 47),
);

/// A message whose embed picture is a moving one behind Discord's media
/// proxy, which serves a still frame when asked for a png.
final _gifMessage = ChatMessage(
  id: 'message-3',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'look at it go',
  sentAt: DateTime(2026, 7, 23, 3, 47),
  embeds: [
    MessageEmbed(
      type: 'rich',
      title: 'Deploy complete',
      image: const MessageEmbedMedia(
        url: 'https://cdn.discordapp.com/attachments/1/cat.gif',
        proxyUrl: 'https://media.discordapp.net/attachments/1/cat.gif',
        width: 1200,
        height: 630,
      ),
    ),
  ],
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'space-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'space-1',
      name: 'general',
      topic: 'General',
      kind: ChannelKind.text,
    ),
  ],
  members: const [_member],
  messages: [_message],
  currentMemberId: 'current-user',
);
