import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

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

    test('sends replies and attachments, then edits and deletes', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      await controller.load();

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '',
        replyToMessageId: 'm4',
        attachments: const [
          PendingAttachment(name: 'proof.txt', path: r'C:\proof.txt', size: 12),
        ],
      );
      final message = controller.workspace!.messages.last;

      expect(sent, isTrue);
      expect(message.attachments.single.fileName, 'proof.txt');
      expect(message.reply?.messageId, 'm4');
      expect(await controller.editMessage(message, 'Edited body'), isTrue);
      expect(controller.workspace!.messages.last.body, 'Edited body');

      await controller.addReaction(message, '✓');
      await Future<void>.delayed(Duration.zero);
      final reacted = controller.workspace!.messages.last;
      expect(reacted.reactions.single.reactedByCurrentUser, isTrue);

      await controller.toggleReaction(reacted, reacted.reactions.single);
      await Future<void>.delayed(Duration.zero);
      expect(controller.workspace!.messages.last.reactions, isEmpty);

      await controller.deleteMessage(message);
      expect(
        controller.workspace!.messages.any((item) => item.id == message.id),
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
