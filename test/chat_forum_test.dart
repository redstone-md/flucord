import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('opens a forum feed and projects a created post', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.openChannel('forge-forum');
    expect(controller.archivedThreadsFor('forge-forum'), hasLength(1));
    final archived = controller.archivedThreadsFor('forge-forum').single;
    expect(controller.workspace!.messagesFor(archived.id), isEmpty);

    await controller.loadForumPostPreview(archived.id);

    expect(
      controller.workspace!.messagesFor(archived.id).single.body,
      'Preview for release-retrospective.',
    );

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

  test('accepts attachment-only posts and rejects duplicate files', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    const attachment = PendingAttachment(
      name: 'capture.png',
      path: r'C:\captures\capture.png',
      size: 128,
    );

    final post = await controller.createForumPost(
      channelId: 'forge-forum',
      name: 'native-capture',
      content: '',
      attachments: const [attachment],
      autoArchiveDurationMinutes: 1440,
    );

    expect(post, isNotNull);
    expect(
      controller.workspace!.messagesFor(post!.id).single.attachments.single,
      isA<MessageAttachment>()
          .having((item) => item.fileName, 'fileName', 'capture.png')
          .having((item) => item.size, 'size', 128),
    );
    expect(
      await controller.createForumPost(
        channelId: 'forge-forum',
        name: 'duplicate-capture',
        content: '',
        attachments: const [attachment, attachment],
        autoArchiveDurationMinutes: 1440,
      ),
      isNull,
    );
  });
}
