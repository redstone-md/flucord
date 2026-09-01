import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/desktop_app_surface.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formats a vetted message into a toast', () async {
    final surface = await _mountedSurface();
    final workspace = surface.chat.workspace!;
    final channel = workspace.channels.firstWhere(
      (item) => item.kind == ChannelKind.text && !item.isThread,
    );
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );
    final message = ChatMessage(
      id: 'native-notification',
      channelId: channel.id,
      authorId: author.id,
      body: '  Native\nmessage   delivery  ',
      sentAt: DateTime.utc(2026, 7, 24),
    );

    await surface.emit(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );

    final toast = surface.notifications.single;
    expect(toast.identifier, 'flucord-native-notification');
    expect(toast.title, '${author.displayName} - #${channel.name}');
    expect(toast.subtitle, workspace.spaceById(channel.spaceId).name);
    expect(toast.body, 'Native message delivery');
    expect(
      toast.link,
      ChannelLink(spaceId: channel.spaceId, channelId: channel.id),
    );
  });

  test('ignores old events and own messages', () async {
    final surface = await _mountedSurface();
    final workspace = surface.chat.workspace!;
    final channel = workspace.channels.firstWhere(
      (item) => item.kind == ChannelKind.text && !item.isThread,
    );
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );
    final message = ChatMessage(
      id: 'not-an-interruption',
      channelId: channel.id,
      authorId: author.id,
      body: 'Skipped',
      sentAt: DateTime.utc(2026, 7, 24),
    );

    await surface.emit(MessageUpsertedEvent(message: message, member: author));
    await surface.emit(
      MessageUpsertedEvent(
        message: ChatMessage(
          id: 'own-message',
          channelId: channel.id,
          authorId: workspace.currentMemberId,
          body: 'Me',
          sentAt: DateTime.utc(2026, 7, 24),
        ),
        member: author,
        isNew: true,
      ),
    );

    expect(surface.notifications, isEmpty);
  });

  test('emits for the channel on screen: focus is the platform fact', () async {
    final surface = await _mountedSurface();
    final workspace = surface.chat.workspace!;
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );
    final message = ChatMessage(
      id: 'on-screen',
      channelId: surface.chat.activeChannelId!,
      authorId: author.id,
      body: 'Already visible',
      sentAt: DateTime.utc(2026, 7, 24),
    );

    await surface.emit(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );

    expect(surface.notifications, hasLength(1));
  });

  test('drops messages for channels the workspace does not know', () async {
    final surface = await _mountedSurface();
    final workspace = surface.chat.workspace!;
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );

    await surface.emit(
      MessageUpsertedEvent(
        message: ChatMessage(
          id: 'unknown-channel',
          channelId: 'no-such-channel',
          authorId: author.id,
          body: 'Where does this even go',
          sentAt: DateTime.utc(2026, 7, 24),
        ),
        member: author,
        isNew: true,
      ),
    );

    expect(surface.notifications, isEmpty);
  });

  test('stays silent while the account is in quiet mode', () async {
    final repository = _QuietChatRepository();
    final surface = await _mountedSurface(repository: repository);
    final workspace = surface.chat.workspace!;
    final channel = workspace.channels.firstWhere(
      (item) => item.kind == ChannelKind.text && !item.isThread,
    );
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );
    final message = ChatMessage(
      id: 'quiet-notification',
      channelId: channel.id,
      authorId: author.id,
      body: 'Should not interrupt',
      sentAt: DateTime.utc(2026, 7, 24),
    );

    expect(surface.chat.suppressesMessageNotifications, isTrue);
    await surface.emit(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );
    expect(surface.notifications, isEmpty);

    repository.settings.quiet = false;
    await surface.emit(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );
    expect(surface.notifications, hasLength(1));
  });

  test('honours mute, the notification level and suppress @everyone', () async {
    final repository = _QuietChatRepository();
    repository.settings.quiet = false;
    final surface = await _mountedSurface(repository: repository);
    final workspace = surface.chat.workspace!;
    final channel = workspace.channels.firstWhere(
      (item) => item.kind == ChannelKind.text && !item.isThread,
    );
    final author = workspace.members.firstWhere(
      (item) => item.id != workspace.currentMemberId,
    );
    ChatMessage message({
      required String id,
      bool mentionsEveryone = false,
      bool mentionsCurrentMember = false,
    }) => ChatMessage(
      id: id,
      channelId: channel.id,
      authorId: author.id,
      body: 'Interruption',
      sentAt: DateTime.utc(2026, 7, 24),
      mentionsEveryone: mentionsEveryone,
      mentionsCurrentMember: mentionsCurrentMember,
    );

    repository.readStates.publish(
      ReadStateSnapshot(
        settings: {
          channel.spaceId: GuildNotificationSettings(
            spaceId: channel.spaceId,
            muted: true,
          ),
        },
      ),
    );
    await surface.emit(
      MessageUpsertedEvent(
        message: message(id: 'muted-guild'),
        member: author,
        isNew: true,
      ),
    );
    expect(surface.notifications, isEmpty);

    repository.readStates.publish(
      ReadStateSnapshot(
        settings: {
          channel.spaceId: GuildNotificationSettings(
            spaceId: channel.spaceId,
            messageNotifications: MessageNotificationLevel.onlyMentions,
            suppressEveryone: true,
          ),
        },
      ),
    );
    await surface.emit(
      MessageUpsertedEvent(
        message: message(id: 'plain'),
        member: author,
        isNew: true,
      ),
    );
    await surface.emit(
      MessageUpsertedEvent(
        message: message(id: 'everyone', mentionsEveryone: true),
        member: author,
        isNew: true,
      ),
    );
    expect(surface.notifications, isEmpty);

    await surface.emit(
      MessageUpsertedEvent(
        message: message(id: 'mention', mentionsCurrentMember: true),
        member: author,
        isNew: true,
      ),
    );
    expect(surface.notifications, hasLength(1));
  });

  test(
    'holds a channel link until the workspace loads, then opens it',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final workspace = WorkspaceController();
      final messages = StreamController<MessageUpsertedEvent>();
      final surface = FlucordAppSurface(
        chat: chat,
        workspace: workspace,
        visible: WindowVisible(),
        onProtocolUri: (_) {},
        incomingMessages: messages.stream,
      );
      addTearDown(chat.dispose);
      addTearDown(workspace.dispose);
      addTearDown(surface.dispose);

      surface.openChannelLink(
        const ChannelLink(spaceId: 'night', channelId: 'night-ops'),
      );
      expect(chat.activeChannelId, isNull);

      await chat.load();

      // The held link was applied the moment the workspace existed. Load's own
      // landing pick follows it, so the channel list selection is what proves
      // the link opened.
      expect(workspace.selectedSpaceId, 'night');
      expect(workspace.selectedChannelId, 'night-ops');

      surface.openChannelLink(
        const ChannelLink(spaceId: 'night', channelId: 'night-ops'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(chat.activeChannelId, 'night-ops');
    },
  );

  test('reports the unread channel count as app state moves', () async {
    final mounted = await _mountedSurface();
    var notified = 0;
    mounted.surface.addListener(() => notified++);
    await mounted.chat.openChannel(mounted.chat.workspace!.channels.first.id);

    expect(
      mounted.surface.unreadChannelCount,
      mounted.chat.workspace!.channels
          .where((channel) => channel.unread)
          .length,
    );
    expect(notified, greaterThan(0));
    expect(mounted.surface.activeChannelId, mounted.chat.activeChannelId);
  });

  test('the window leaving the screen reaches what suspends on it', () {
    final mounted = _MountedSurface(
      ChatController(MockChatRepository(latency: Duration.zero)),
    );
    var notified = 0;
    mounted.visible.addListener(() => notified++);

    // A visibility event repeated for a window that never left the screen
    // says nothing: the desktop chrome sends these in bursts.
    mounted.surface.setWindowVisible(true);
    expect(mounted.visible.inView, isTrue);
    expect(notified, 0);

    mounted.surface.setWindowVisible(false);
    expect(mounted.visible.inView, isFalse);
    expect(notified, 1);
  });

  test('losing the focus does not take a visible window off the screen', () {
    final mounted = _MountedSurface(
      ChatController(MockChatRepository(latency: Duration.zero)),
    );

    mounted.surface.setApplicationActive(false);

    // An unfocused window is still on screen, and still watched: the chat's
    // read state follows the focus, suspension follows the screen.
    expect(mounted.visible.inView, isTrue);
  });
}

/// A surface mounted over a chat controller, with an injectable message feed
/// standing in for the repository's events, collecting what the desktop
/// chrome would receive.
class _MountedSurface {
  _MountedSurface(this.chat)
    : workspace = WorkspaceController(),
      visible = WindowVisible(),
      messages = StreamController<MessageUpsertedEvent>() {
    surface = FlucordAppSurface(
      chat: chat,
      workspace: workspace,
      visible: visible,
      onProtocolUri: (_) {},
      incomingMessages: messages.stream,
    );
    addTearDown(chat.dispose);
    addTearDown(surface.dispose);
    surface.messageNotifications.listen(notifications.add);
  }

  final ChatController chat;
  final WorkspaceController workspace;
  final WindowVisible visible;
  final StreamController<MessageUpsertedEvent> messages;
  late final FlucordAppSurface surface;
  final List<DesktopMessageNotification> notifications = [];

  Future<void> emit(MessageUpsertedEvent event) async {
    notifications.clear();
    messages.add(event);
    await Future<void>.delayed(Duration.zero);
  }
}

Future<_MountedSurface> _mountedSurface({ChatRepository? repository}) async {
  final mounted = _MountedSurface(
    ChatController(repository ?? MockChatRepository(latency: Duration.zero)),
  );
  await mounted.chat.load();
  return mounted;
}

/// A transport that behaves like the demo one but also carries settings, so
/// the notification path can be exercised against quiet mode.
final class _QuietChatRepository implements ChatRepository {
  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );
  final _QuietSettings settings = _QuietSettings();
  final _StubReadStates readStates = _StubReadStates();

  @override
  UserSettingsRepository? get userSettings => settings;

  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;

  @override
  ReadStateRepository? get readState => readStates;

  @override
  Stream<ChatRepositoryEvent> get events => _delegate.events;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) =>
      _delegate.loadChannelHistory(channelId, beforeMessageId: beforeMessageId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _delegate.saveChannelActivity(channel);

  @override
  Future<void> close() => _delegate.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A read-state store that only ever answers questions: the notification path
/// reads settings and never writes them.
final class _StubReadStates implements ReadStateRepository {
  final StreamController<ReadStateSnapshot> _updates =
      StreamController.broadcast();
  ReadStateSnapshot _current = ReadStateSnapshot.empty;

  void publish(ReadStateSnapshot snapshot) {
    _current = snapshot;
    _updates.add(snapshot);
  }

  @override
  ReadStateSnapshot get current => _current;

  @override
  Stream<ReadStateSnapshot> get updates => _updates.stream;

  @override
  Future<void> acknowledge(
    ConversationChannel channel, {
    required String messageId,
    bool immediate = false,
  }) async {}

  @override
  Future<void> markUnread(
    ConversationChannel channel, {
    required String messageId,
    int mentionCount = 0,
  }) async {}

  @override
  Future<void> markSpaceRead(
    String spaceId,
    Iterable<ConversationChannel> channels,
  ) async {}

  @override
  Future<void> updateSpaceNotificationSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  ) async {}

  @override
  Future<void> updateChannelNotificationOverride({
    required String spaceId,
    required String channelId,
    required ChannelNotificationOverridePatch patch,
  }) async {}

  @override
  Future<void> flush() async {}
}

final class _QuietSettings implements UserSettingsRepository {
  bool quiet = true;

  @override
  UserSettings? get current =>
      UserSettings(notifications: NotificationPreferences(quietMode: quiet));

  @override
  bool get isLoaded => true;

  @override
  Object? get lastWriteError => null;

  @override
  Stream<UserSettings> get updates => const Stream.empty();

  @override
  Future<UserSettings> load() async => current!;

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {}

  @override
  Future<void> flush() async {}
}
