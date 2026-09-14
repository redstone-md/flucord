import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('forwards a supported message into another native channel', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final source = controller.workspace!.messages.firstWhere(
      (message) => message.id == 'm4',
    );

    final sent = await controller.forwardMessage(source, 'forge-native');

    expect(sent, isTrue);
    final forwarded = controller.workspace!.messagesFor('forge-native').last;
    expect(forwarded.isForwarded, isTrue);
    expect(forwarded.reference?.messageId, source.id);
    expect(forwarded.snapshots.single.body, source.body);
  });

  test('forwards into the timeline a voice channel carries', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final source = controller.workspace!.messages.firstWhere(
      (message) => message.id == 'm4',
    );
    final voice = controller.workspace!.channels.firstWhere(
      (channel) => channel.kind == ChannelKind.voice,
    );

    final sent = await controller.forwardMessage(source, voice.id);

    expect(sent, isTrue);
    expect(
      controller.workspace!.messagesFor(voice.id).last.snapshots.single.body,
      source.body,
    );
  });

  test('rejects destinations that cannot accept text messages', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final source = controller.workspace!.messages.firstWhere(
      (message) => message.id == 'm4',
    );
    final forum = controller.workspace!.channels.firstWhere(
      (channel) => channel.kind == ChannelKind.forum,
    );

    final sent = await controller.forwardMessage(source, forum.id);

    expect(sent, isFalse);
    expect(
      controller.workspace!.messagesFor(forum.id).where((message) {
        return message.reference?.type == DiscordMessageReferenceType.forward;
      }),
      isEmpty,
    );
  });
}
