import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  test('projects a created message thread into the workspace', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final source = controller.workspace!.messages.firstWhere(
      (message) => message.id == 'm4',
    );

    final thread = await controller.createThreadFromMessage(
      source,
      name: '  release follow-up  ',
      autoArchiveDurationMinutes: 1440,
    );

    expect(thread?.id, source.id);
    expect(thread?.name, 'release follow-up');
    expect(thread?.isThread, isTrue);
    expect(thread?.parentId, source.channelId);
    expect(controller.workspace!.channelById(source.id), same(thread));
  });
}
