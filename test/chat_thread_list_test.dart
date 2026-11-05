import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  test('pages through the threads under a channel', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.loadThreads('forge-native');
    expect(
      controller
          .threadsFor('forge-native')
          .where((thread) => thread.isArchived),
      hasLength(1),
    );
    expect(controller.canLoadMoreThreads('forge-native'), isTrue);
    expect(controller.threadsError('forge-native'), isNull);

    await controller.loadThreads('forge-native');
    final archived = controller
        .threadsFor('forge-native')
        .where((thread) => thread.isArchived);
    expect(archived.map((thread) => thread.name).toSet(), {
      'release-retrospective',
      'transport-notes',
    });
    expect(controller.canLoadMoreThreads('forge-native'), isFalse);

    await controller.loadThreads('forge-native', refresh: true);
    expect(controller.canLoadMoreThreads('forge-native'), isTrue);
  });

  test('other tags start the list over and outlive the load before', () async {
    final controller = ChatController(
      MockChatRepository(latency: const Duration(milliseconds: 5)),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final untagged = controller.loadThreads('forge-forum');
    final tagged = controller.loadThreads(
      'forge-forum',
      tagIds: const {'tag-client'},
    );

    await untagged;
    // The untagged answer came back first and was dropped, so the tagged
    // load is still the one in flight.
    expect(controller.isLoadingThreads('forge-forum'), isTrue);
    await tagged;
    expect(controller.isLoadingThreads('forge-forum'), isFalse);
    expect(controller.canLoadMoreThreads('forge-forum'), isTrue);
  });
}
