import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';

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

    test('loads and toggles pinned messages', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.loadPinnedMessages('forge-general');
      final pinned = controller
          .pinnedMessages('forge-general')!
          .messages
          .single;
      expect(pinned.id, 'm4');

      await controller.togglePin(pinned);
      expect(controller.pinnedMessages('forge-general')!.messages, isEmpty);
      expect(
        controller.workspace!.messagesFor('forge-general').last.isPinned,
        isFalse,
      );
    });

    test('tracks live unread, mentions, presence, and typing', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.openChannel('forge-general');

      repository.emit(
        MessageUpsertedEvent(
          message: ChatMessage(
            id: 'incoming-1',
            channelId: 'forge-native',
            authorId: 'lena',
            body: 'Mention from another channel',
            sentAt: DateTime.now(),
          ),
          isNew: true,
          mentionsCurrentMember: true,
        ),
      );
      repository.emit(
        const PresenceChangedEvent(memberId: 'lena', presence: Presence.online),
      );
      repository.emit(
        const TypingStartedEvent(channelId: 'forge-general', memberId: 'lena'),
      );
      await Future<void>.delayed(Duration.zero);

      final unread = controller.workspace!.channelById('forge-native');
      expect(unread.unread, isTrue);
      expect(unread.mentionCount, 1);
      expect(
        controller.workspace!.memberById('lena').presence,
        Presence.online,
      );
      expect(controller.typingMembersFor('forge-general').single.id, 'lena');

      await controller.openChannel('forge-native');
      final read = controller.workspace!.channelById('forge-native');
      expect(read.unread, isFalse);
      expect(read.mentionCount, 0);
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

final class _EventRepository implements ChatRepository {
  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  void emit(ChatRepositoryEvent event) => _events.add(event);

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Future<ChannelHistory> loadChannelHistory(String channelId) =>
      _delegate.loadChannelHistory(channelId);

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) =>
      _delegate.loadPinnedMessages(channelId);

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  }) => _delegate.sendMessage(
    channelId: channelId,
    authorId: authorId,
    body: body,
    attachments: attachments,
    replyToMessageId: replyToMessageId,
  );

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) => _delegate.editMessage(
    channelId: channelId,
    messageId: messageId,
    body: body,
  );

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.deleteMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _delegate.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _delegate.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.pinMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.unpinMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> startTyping(String channelId) =>
      _delegate.startTyping(channelId);

  @override
  Future<void> close() async {}
}
