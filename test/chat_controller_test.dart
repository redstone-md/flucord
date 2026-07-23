import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  group('ChatController', () {
    test('loads workspace and appends a sent message', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );

      await controller.load();
      final initialCount = controller.workspace!.messages.length;
      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '  Repository boundary holds.  ',
      );

      expect(controller.state, ChatLoadState.ready);
      expect(sent, isTrue);
      expect(controller.workspace!.messages, hasLength(initialCount + 1));
      expect(
        controller.workspace!.messages.last.body,
        'Repository boundary holds.',
      );
    });

    test('rejects empty content', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      await controller.load();

      expect(
        await controller.sendMessage(channelId: 'forge-general', body: '   '),
        isFalse,
      );
    });
  });

  test('workspace state remains independent from server state', () async {
    final repository = MockChatRepository(latency: Duration.zero);
    final workspace = await repository.loadWorkspace();
    final controller = WorkspaceController();

    controller.reconcile(workspace);
    controller.setQuery('old filter');
    controller.selectSpace(workspace, 'night');

    expect(controller.selectedSpaceId, 'night');
    expect(controller.selectedChannelId, 'night-ops');
    expect(controller.query, isEmpty);
  });
}
