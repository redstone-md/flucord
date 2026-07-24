import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/channel_link.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
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
