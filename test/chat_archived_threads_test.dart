import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  test('merges and deduplicates archived thread pages', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.loadArchivedThreads('forge-native');

    expect(
      controller
          .archivedThreadsFor('forge-native')
          .map((thread) => thread.name),
      ['release-retrospective'],
    );
    expect(controller.canLoadMoreArchivedThreads('forge-native'), isTrue);
    expect(controller.archivedThreadsError('forge-native'), isNull);

    await controller.loadArchivedThreads('forge-native');

    final threads = controller.archivedThreadsFor('forge-native');
    expect(threads.map((thread) => thread.name), [
      'release-retrospective',
      'transport-notes',
    ]);
    expect(threads.map((thread) => thread.id).toSet(), hasLength(2));
    expect(threads.last.isLocked, isTrue);
    expect(controller.canLoadMoreArchivedThreads('forge-native'), isFalse);
    expect(
      controller.workspace!.channelById(threads.last.id),
      same(threads.last),
    );
  });

  test('refresh replaces the archived pagination projection', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadArchivedThreads('forge-native');
    await controller.loadArchivedThreads('forge-native');
    expect(controller.archivedThreadsFor('forge-native'), hasLength(2));

    await controller.loadArchivedThreads('forge-native', refresh: true);

    expect(controller.archivedThreadsFor('forge-native'), hasLength(1));
    expect(controller.canLoadMoreArchivedThreads('forge-native'), isTrue);
  });
}
