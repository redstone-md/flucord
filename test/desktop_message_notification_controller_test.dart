import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/channel_link.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/platform/desktop_message_notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds and activates a native message notification', () async {
    final gateway = _NotificationGateway();
    final controller = DesktopMessageNotificationController(
      isFocused: () async => false,
      gateway: gateway,
    );
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    ChannelLink? activatedLink;
    addTearDown(chat.dispose);
    addTearDown(controller.dispose);
    await chat.load();
    controller.attach(
      chatController: chat,
      onActivateLink: (link) async => activatedLink = link,
    );
    await controller.initialize();
    final workspace = chat.workspace!;
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

    await controller.notify(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );

    expect(gateway.initializeCount, 1);
    expect(gateway.requests, hasLength(1));
    final request = gateway.requests.single;
    expect(request.identifier, 'flucord-native-notification');
    expect(request.title, '${author.displayName} - #${channel.name}');
    expect(request.subtitle, workspace.spaceById(channel.spaceId).name);
    expect(request.body, 'Native message delivery');

    await request.onClick();
    expect(activatedLink?.spaceId, channel.spaceId);
    expect(activatedLink?.channelId, channel.id);
  });

  test(
    'suppresses the visible active channel and ignores old events',
    () async {
      final gateway = _NotificationGateway();
      final controller = DesktopMessageNotificationController(
        isFocused: () async => true,
        gateway: gateway,
      );
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      addTearDown(chat.dispose);
      addTearDown(controller.dispose);
      await chat.load();
      controller.attach(chatController: chat, onActivateLink: (_) async {});
      await controller.initialize();
      final workspace = chat.workspace!;
      final author = workspace.members.firstWhere(
        (item) => item.id != workspace.currentMemberId,
      );
      final message = ChatMessage(
        id: 'suppressed-notification',
        channelId: chat.activeChannelId!,
        authorId: author.id,
        body: 'Already visible',
        sentAt: DateTime.utc(2026, 7, 24),
      );

      await controller.notify(
        MessageUpsertedEvent(message: message, member: author, isNew: true),
      );
      await controller.notify(
        MessageUpsertedEvent(message: message, member: author),
      );

      expect(gateway.requests, isEmpty);
    },
  );

  test('stays silent while the account is in quiet mode', () async {
    final gateway = _NotificationGateway();
    final controller = DesktopMessageNotificationController(
      isFocused: () async => false,
      gateway: gateway,
    );
    final repository = _QuietChatRepository();
    final chat = ChatController(repository);
    addTearDown(chat.dispose);
    addTearDown(controller.dispose);
    await chat.load();
    controller.attach(chatController: chat, onActivateLink: (_) async {});
    await controller.initialize();
    final workspace = chat.workspace!;
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

    expect(chat.suppressesMessageNotifications, isTrue);
    await controller.notify(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );

    expect(gateway.requests, isEmpty);

    repository.settings.quiet = false;
    await controller.notify(
      MessageUpsertedEvent(message: message, member: author, isNew: true),
    );

    expect(gateway.requests, hasLength(1));
  });
}

/// A transport that behaves like the demo one but also carries settings, so
/// the notification path can be exercised against quiet mode.
final class _QuietChatRepository implements ChatRepository {
  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );
  final _QuietSettings settings = _QuietSettings();

  @override
  UserSettingsRepository? get userSettings => settings;

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

final class _NotificationGateway implements DesktopNotificationGateway {
  final List<DesktopNotificationRequest> requests = [];
  int initializeCount = 0;

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> dispose() async {}
}
