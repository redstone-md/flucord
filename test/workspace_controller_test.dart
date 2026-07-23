import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
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

  test('workspace selection supports an empty direct message inbox', () {
    final workspace = ChatWorkspace(
      spaces: const [CommunitySpace.directMessages()],
      channels: const [],
      members: const [],
      messages: const [],
      currentMemberId: 'bot-1',
    );
    final controller = WorkspaceController();

    controller.reconcile(workspace);

    expect(controller.selectedSpaceId, CommunitySpace.directMessagesId);
    expect(controller.selectedChannelId, isNull);
  });

  test(
    'workspace selection retains and clears an explicit message target',
    () async {
      final repository = MockChatRepository(latency: Duration.zero);
      final workspace = await repository.loadWorkspace();
      final controller = WorkspaceController();
      controller.reconcile(workspace);

      controller.selectMessage('forge-design', 'design-mention');
      expect(controller.selectedChannelId, 'forge-design');
      expect(controller.targetMessageId, 'design-mention');

      controller.setQuery('signal');
      expect(controller.targetMessageId, isNull);
      controller.selectMessage('forge-design', 'design-mention');
      controller.selectChannel('forge-design');
      expect(controller.targetMessageId, isNull);
    },
  );
}
