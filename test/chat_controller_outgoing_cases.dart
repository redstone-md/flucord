part of 'chat_controller_test.dart';

/// Messages on their way: shown at once, settled by Discord's answer.
void _outgoingMessageTests() {
  group('a message on its way', () {
    late _EventRepository repository;
    late ChatController controller;

    setUp(() async {
      repository = _EventRepository();
      controller = ChatController(repository);
      await controller.load();
    });
    tearDown(() => controller.dispose());

    ChatMessage delivered(String body, {String id = 'delivered-1'}) =>
        ChatMessage(
          id: id,
          channelId: 'forge-general',
          authorId: controller.workspace!.currentMemberId,
          body: body,
          sentAt: DateTime.now(),
        );

    List<String> heldBodies() => [
      for (final message in controller.workspace!.messagesFor('forge-general'))
        message.body,
    ];

    test('shows at once as sending, then becomes the real message', () async {
      final answer = Completer<ChatMessage>();
      repository.answerSend = (_, _) => answer.future;

      final sent = controller.sendMessage(
        channelId: 'forge-general',
        body: 'On its way',
      );

      final outgoing = controller.outgoingIn('forge-general').single;
      expect(outgoing.message.body, 'On its way');
      expect(outgoing.delivery, isA<OutgoingSending>());
      expect(heldBodies(), isNot(contains('On its way')));
      await Future<void>.delayed(Duration.zero);
      expect(repository.sentNonces.single, outgoing.nonce);

      answer.complete(delivered('On its way'));
      expect(await sent, isTrue);
      expect(controller.outgoingIn('forge-general'), isEmpty);
      expect(heldBodies(), contains('On its way'));
    });

    test('is replaced by the echo that carries its nonce', () async {
      repository.answerSend = (_, _) => Completer<ChatMessage>().future;
      unawaited(
        controller.sendMessage(channelId: 'forge-general', body: 'Echo me'),
      );
      await Future<void>.delayed(Duration.zero);

      repository.emit(
        MessageUpsertedEvent(
          message: delivered('Echo me'),
          isNew: true,
          nonce: repository.sentNonces.single,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.outgoingIn('forge-general'), isEmpty);
      expect(heldBodies(), contains('Echo me'));
    });

    test('stays in the timeline, failed, when the send fails', () async {
      final refusal = StateError('refused');
      repository.answerSend = (_, _) async => throw refusal;

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: 'Refused',
      );

      expect(sent, isFalse);
      final failed = controller.outgoingIn('forge-general').single;
      expect(failed.message.body, 'Refused');
      expect(failed.delivery, isA<OutgoingFailed>());
      expect((failed.delivery as OutgoingFailed).error, same(refusal));
    });

    test('is sent again with the same nonce on retry', () async {
      repository.answerSend = (_, _) async => throw StateError('refused');
      await controller.sendMessage(channelId: 'forge-general', body: 'Again');
      repository.answerSend = (_, _) async => delivered('Again');

      final sent = await controller.retrySend(
        controller.outgoingIn('forge-general').single,
      );

      expect(sent, isTrue);
      expect(repository.sentNonces, hasLength(2));
      expect(repository.sentNonces.toSet(), hasLength(1));
      expect(controller.outgoingIn('forge-general'), isEmpty);
      expect(heldBodies(), contains('Again'));
    });

    test('is gone for good once deleted unsent', () async {
      repository.answerSend = (_, _) async => throw StateError('refused');
      await controller.sendMessage(channelId: 'forge-general', body: 'Drop');

      controller.discardSend(controller.outgoingIn('forge-general').single);

      expect(controller.outgoingIn('forge-general'), isEmpty);
      expect(heldBodies(), isNot(contains('Drop')));
      expect(repository.sentNonces, hasLength(1));
    });

    test('goes out after the message written before it', () async {
      final first = Completer<ChatMessage>();
      repository.answerSend = (_, _) => first.future;
      unawaited(
        controller.sendMessage(channelId: 'forge-general', body: 'First'),
      );
      final second = controller.sendMessage(
        channelId: 'forge-general',
        body: 'Second',
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.sentNonces, hasLength(1));
      expect(controller.outgoingIn('forge-general'), hasLength(2));

      repository.answerSend = (_, _) async => delivered('Second', id: 'd-2');
      first.complete(delivered('First'));
      expect(await second, isTrue);
      expect(repository.sentNonces, hasLength(2));
      expect(repository.sentNonces.toSet(), hasLength(2));
    });

    test('shows how much of its files has gone out', () async {
      final answer = Completer<ChatMessage>();
      repository.answerSend = (_, onUploadProgress) {
        onUploadProgress!(0.5);
        return answer.future;
      };

      unawaited(
        controller.sendMessage(
          channelId: 'forge-general',
          body: '',
          attachments: const [
            PendingAttachment(name: 'a.png', path: '/tmp/a.png', size: 10),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final outgoing = controller.outgoingIn('forge-general').single;
      expect(outgoing.attachments.single.name, 'a.png');
      expect((outgoing.delivery as OutgoingSending).uploadProgress, 0.5);
      answer.complete(delivered(''));
    });

    test('an upload that starts again does not move the bar back', () async {
      final answer = Completer<ChatMessage>();
      repository.answerSend = (_, onUploadProgress) {
        onUploadProgress!(0.6);
        // The transport sends the files again from the start.
        onUploadProgress(0.1);
        return answer.future;
      };

      unawaited(
        controller.sendMessage(
          channelId: 'forge-general',
          body: '',
          attachments: const [
            PendingAttachment(name: 'a.png', path: '/tmp/a.png', size: 10),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final outgoing = controller.outgoingIn('forge-general').single;
      expect((outgoing.delivery as OutgoingSending).uploadProgress, 0.6);
      answer.complete(delivered(''));
    });

    test('a send that lands after an account switch stays with the old '
        'account', () async {
      final answer = Completer<ChatMessage>();
      repository.answerSend = (_, _) => answer.future;
      final sent = controller.sendMessage(
        channelId: 'forge-general',
        body: 'From the last account',
      );
      await Future<void>.delayed(Duration.zero);

      await controller.useRepository(_EventRepository());
      answer.complete(delivered('From the last account'));
      await sent;

      expect(heldBodies(), isNot(contains('From the last account')));
    });
  });
}
