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

  test('votes, changes the vote, takes it back, and lists voters', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.createPoll(
      channelId: 'forge-general',
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 24,
      ),
    );
    ChatMessage poll() => controller.workspace!.messages.last;
    List<int> counts() => [for (final a in poll().poll!.answers) a.count];

    expect(controller.canVoteInPolls, isTrue);
    expect(await controller.votePoll(poll(), {1}), isTrue);
    expect(counts(), [1, 0]);
    expect(poll().poll!.ownVote, {1});

    expect(await controller.votePoll(poll(), {2}), isTrue);
    expect(counts(), [0, 1]);

    final voters = await controller.loadPollVoters(
      poll(),
      poll().poll!.answers.last,
      null,
    );
    expect(voters.users.map((user) => user.id), [
      controller.workspace!.currentMemberId,
    ]);

    expect(await controller.votePoll(poll(), const {}), isTrue);
    expect(counts(), [0, 0]);
    expect(poll().poll!.ownVote, isEmpty);
  });

  test('an ended poll takes no vote', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.createPoll(
      channelId: 'forge-general',
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 24,
      ),
    );
    await controller.endPoll(controller.workspace!.messages.last);

    expect(
      await controller.votePoll(controller.workspace!.messages.last, {1}),
      isFalse,
    );
    expect(controller.workspace!.messages.last.poll!.totalVotes, 0);
  });
}
