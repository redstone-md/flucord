import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('creates, normalizes, and ends an application poll', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final created = await controller.createPoll(
      channelId: 'forge-general',
      poll: PendingPoll(
        question: '  Which build ships?  ',
        answers: const ['  Stable  ', 'Canary'],
        durationHours: 24,
        allowMultiselect: true,
      ),
    );

    expect(created, isTrue);
    final message = controller.workspace!.messages.last;
    expect(message.body, isEmpty);
    expect(message.poll?.question, 'Which build ships?');
    expect(message.poll?.answers.map((answer) => answer.text), [
      'Stable',
      'Canary',
    ]);
    expect(message.poll?.allowMultiselect, isTrue);
    expect(message.poll?.isFinalized, isFalse);

    expect(await controller.endPoll(message), isTrue);
    expect(controller.workspace!.messages.last.poll?.isFinalized, isTrue);
  });

  test('rejects invalid polls before reaching the repository', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(
      await controller.createPoll(
        channelId: 'forge-general',
        poll: PendingPoll(
          question: 'Only one answer?',
          answers: const ['Yes'],
          durationHours: 24,
        ),
      ),
      isFalse,
    );
    expect(
      await controller.createPoll(
        channelId: 'forge-general',
        poll: PendingPoll(
          question: 'Too long?',
          answers: const ['Yes', 'No'],
          durationHours: PendingPoll.maxDurationHours + 1,
        ),
      ),
      isFalse,
    );
  });

  test('accepts the timeline a voice channel carries', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final poll = PendingPoll(
      question: 'Keep the bench open?',
      answers: const ['Yes', 'No'],
      durationHours: 24,
    );

    expect(
      await controller.createPoll(channelId: 'forge-voice', poll: poll),
      isTrue,
    );
    expect(
      await controller.createPoll(channelId: 'forge-forum', poll: poll),
      isFalse,
    );
    expect(
      controller.workspace!.messagesFor('forge-voice').last.poll?.question,
      'Keep the bench open?',
    );
  });
}
