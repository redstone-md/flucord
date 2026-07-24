import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/platform/desktop_protocol_router.dart';

void main() {
  test('retains an OAuth callback until the application attaches', () async {
    final router = DesktopProtocolRouter();
    final received = <Uri>[];
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final workspace = WorkspaceController();
    addTearDown(chat.dispose);
    addTearDown(workspace.dispose);
    await chat.load();

    router.receive(
      'flucord://oauth/discord/callback?code=code-1&state=state-1',
    );
    router.attach(
      chatController: chat,
      workspaceController: workspace,
      onProtocolUri: received.add,
    );

    expect(received, [
      Uri.parse('flucord://oauth/discord/callback?code=code-1&state=state-1'),
    ]);
  });

  test('opens channel links through the shared workspace boundary', () async {
    final router = DesktopProtocolRouter();
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final workspace = WorkspaceController();
    addTearDown(chat.dispose);
    addTearDown(workspace.dispose);
    await chat.load();
    workspace.reconcile(chat.workspace!);
    router.attach(
      chatController: chat,
      workspaceController: workspace,
      onProtocolUri: (_) => fail('Channel link escaped to OAuth'),
    );

    router.receive('flucord://channels/night/night-ops');
    await Future<void>.delayed(Duration.zero);

    expect(workspace.selectedSpaceId, 'night');
    expect(workspace.selectedChannelId, 'night-ops');
    expect(chat.activeChannelId, 'night-ops');
  });

  test('ignores foreign schemes and detaches callbacks', () async {
    final router = DesktopProtocolRouter();
    final received = <Uri>[];
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final workspace = WorkspaceController();
    addTearDown(chat.dispose);
    addTearDown(workspace.dispose);
    router.attach(
      chatController: chat,
      workspaceController: workspace,
      onProtocolUri: received.add,
    );

    router.receive('https://discord.com/oauth2/authorize');
    router.detach();
    router.receive('flucord://oauth/discord/callback?code=late');

    expect(received, isEmpty);
  });
}
