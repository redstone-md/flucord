import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  test('opens a forum feed and projects a created post', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.openChannel('forge-forum');
    expect(controller.archivedThreadsFor('forge-forum'), hasLength(1));

    final post = await controller.createForumPost(
      channelId: 'forge-forum',
      name: '  sqlite-v13  ',
      content: '  Forum metadata survives restart.  ',
      autoArchiveDurationMinutes: 1440,
      appliedTagIds: const ['tag-client'],
    );

    expect(post?.name, 'sqlite-v13');
    expect(post?.parentId, 'forge-forum');
    expect(post?.appliedTagIds, ['tag-client']);
    expect(controller.workspace!.channelById(post!.id), same(post));
    expect(
      controller.workspace!.messagesFor(post.id).single.body,
      'Forum metadata survives restart.',
    );
  });

  test('rejects unknown or duplicate forum tags', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    Future<Object?> create(List<String> tags) => controller.createForumPost(
      channelId: 'forge-forum',
      name: 'invalid-tags',
      content: 'Should not be created.',
      autoArchiveDurationMinutes: 1440,
      appliedTagIds: tags,
    );

    expect(await create(['missing']), isNull);
    expect(await create(['tag-client', 'tag-client']), isNull);
  });
}
