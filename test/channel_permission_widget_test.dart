import 'dart:async';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_profile.dart';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/message_action_bar.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _guild = 'guild-1';
const _me = 'member-1';
const _other = 'member-2';

void main() {
  testWidgets('the sidebar lists only what VIEW_CHANNEL survives', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(find.byKey(const ValueKey('channel-general')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-announcements')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-vault')), findsNothing);
    // A category the account cannot see into loses its header too, rather
    // than standing there empty.
    expect(find.byKey(const ValueKey('category-cat-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-cat-secret')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel without SEND_MESSAGES trades its composer for a '
      'notice', (tester) async {
    await _pumpShell(tester);

    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('read-only-channel-notice')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('channel-announcements')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(
      find.byKey(const ValueKey('read-only-channel-notice')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the read-only notice fits a compact window', (tester) async {
    await _pumpShell(tester, size: const Size(700, 620));
    await tester.tap(find.byTooltip('Choose channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('announcements').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('read-only-channel-notice')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the message toolbar offers only permitted actions', (
    tester,
  ) async {
    await _pumpShell(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-m1'))),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-reaction-m1')), findsOneWidget);
    // Nothing in this guild grants MANAGE_MESSAGES, PIN_MESSAGES or
    // CREATE_PUBLIC_THREADS, and the message belongs to somebody else.
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byTooltip('Pin'), findsNothing);
    expect(find.byKey(const ValueKey('create-thread-m1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a permitted toolbar keeps every control', (tester) async {
    await _pumpActionBar(tester, ChannelCapabilities.unrestricted);

    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-reaction-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-thread-m1')), findsOneWidget);
    expect(find.byTooltip('Pin'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a toolbar with no permissions keeps nothing', (tester) async {
    await _pumpActionBar(tester, ChannelCapabilities.none);

    expect(find.byTooltip('Reply'), findsNothing);
    expect(find.byKey(const ValueKey('add-reaction-m1')), findsNothing);
    expect(find.byKey(const ValueKey('create-thread-m1')), findsNothing);
    expect(find.byTooltip('Pin'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the toolbar fits a compact window', (tester) async {
    await _pumpActionBar(
      tester,
      ChannelCapabilities.unrestricted,
      size: const Size(360, 640),
    );

    expect(find.byType(MessageActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the composer hides its upload control without ATTACH_FILES', (
    tester,
  ) async {
    await _pumpComposer(tester, canAttachFiles: true);
    expect(find.byKey(const ValueKey('add-attachment')), findsOneWidget);

    await _pumpComposer(tester, canAttachFiles: false);
    expect(find.byKey(const ValueKey('add-attachment')), findsNothing);
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1280, 860),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    FlucordApp(
      bootstrap: AppBootstrap(
        initialRepository: _PermissionRepository(),
        initialSessionMode: SessionMode.demo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpActionBar(
  WidgetTester tester,
  ChannelCapabilities capabilities, {
  Size size = const Size(900, 640),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MessageActionBar(
            message: _workspace().messages.single,
            workspace: _workspace(),
            capabilities: capabilities,
            isCurrentUser: false,
            onReply: () {},
            onAddReaction: (_) {},
            onReactionPickerToggled: (_) {},
            onShowReactionDetails: (_) {},
            onCreateThread: () {},
            onForward: () {},
            onToggleSuppressEmbeds: () {},
            onEdit: () {},
            onTogglePin: () {},
            onDelete: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required bool canAttachFiles,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: MessageComposer(
          channelId: 'general',
          channelName: 'general',
          spaceName: 'The Forge',
          customEmojis: const [],
          guildStickers: const [],
          isSending: false,
          canAttachFiles: canAttachFiles,
          onSend: (_, _, _, _) async => true,
          onCreatePoll: (_) async => true,
          onSendStickers: (_) async => true,
          onCancelReply: () {},
          onTyping: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DiscordPermissionOverwrite _deny(BigInt mask) =>
    DiscordPermissionOverwrite(id: _guild, allow: BigInt.zero, deny: mask);

ConversationChannel _channel(
  String id, {
  required String parentId,
  required int position,
  BigInt? denied,
}) => ConversationChannel(
  id: id,
  spaceId: _guild,
  name: id,
  topic: '',
  kind: ChannelKind.text,
  position: position,
  parentId: parentId,
  permissionOverwrites: {if (denied != null) _guild: _deny(denied)},
);

Member _member(String id, String name) => Member(
  id: id,
  displayName: name,
  initials: name.substring(0, 1),
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff456b5a,
  spaceIds: const {_guild},
  // An ordinary member of the guild, holding no roles beyond `@everyone`.
  membershipsBySpace: const {_guild: GuildMembership()},
);

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guild,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  categories: const [
    ChannelCategory(
      id: 'cat-open',
      spaceId: _guild,
      name: 'Operations',
      position: 0,
    ),
    ChannelCategory(
      id: 'cat-secret',
      spaceId: _guild,
      name: 'Vault',
      position: 1,
    ),
  ],
  channels: [
    _channel('general', parentId: 'cat-open', position: 0),
    _channel(
      'announcements',
      parentId: 'cat-open',
      position: 1,
      denied: DiscordPermissions.sendMessages,
    ),
    _channel(
      'vault',
      parentId: 'cat-secret',
      position: 2,
      denied: DiscordPermissions.viewChannel,
    ),
  ],
  roles: [
    CommunityRole(
      id: _guild,
      spaceId: _guild,
      name: '@everyone',
      position: 0,
      permissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.readMessageHistory,
        DiscordPermissions.sendMessages,
        DiscordPermissions.addReactions,
        DiscordPermissions.attachFiles,
      ]),
    ),
  ],
  members: [_member(_me, 'Ada'), _member(_other, 'Jack')],
  messages: [
    ChatMessage(
      id: 'm1',
      channelId: 'general',
      authorId: _other,
      body: 'Bench notes are in.',
      sentAt: DateTime.utc(2026, 7, 26, 9),
    ),
  ],
  currentMemberId: _me,
);

/// A transport that serves one fixed, permission-shaped workspace.
final class _PermissionRepository implements ChatRepository {
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  @override
  StageRepository? get stages => null;

  @override
  SoundboardRepository? get soundboard => null;

  @override
  GifRepository? get gifs => null;

  @override
  ApplicationCommandRepository? get applicationCommands => null;

  @override
  MessageComponentRepository? get messageComponents => null;

  @override
  GoLiveRepository? get goLive => null;

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  DirectCallService? get directCalls => null;

  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;

  @override
  Future<ChatWorkspace> loadWorkspace() async => _workspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) async => ChannelHistoryPage(
    history: ChannelHistory(
      channelId: channelId,
      messages: _workspace().messagesFor(channelId),
      members: _workspace().members,
    ),
    hasMore: false,
  );

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async =>
      ChannelHistory(
        channelId: channelId,
        messages: const [],
        members: const [],
      );

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {}

  @override
  Future<void> startTyping(String channelId) async {}

  @override
  Future<void> close() async => _events.close();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of '
    'this fixture',
  );
}
