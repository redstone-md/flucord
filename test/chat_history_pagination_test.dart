import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';

void main() {
  test('merges older pages, removes overlap, and marks exhaustion', () async {
    final repository = _PagedRepository([
      _page(['m2', 'm3'], hasMore: true),
      _page(['m1', 'm2'], hasMore: false),
    ]);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);

    await controller.load();
    await _settleController();

    expect(controller.canLoadOlderMessages('channel-1'), isTrue);
    await controller.loadOlderMessages('channel-1');

    expect(repository.cursors, [null, 'm2']);
    expect(
      controller.workspace!.messagesFor('channel-1').map((item) => item.id),
      ['m1', 'm2', 'm3'],
    );
    expect(controller.canLoadOlderMessages('channel-1'), isFalse);
  });

  test('retains pagination after an error and supports retry', () async {
    final repository = _PagedRepository([
      _page(['m2'], hasMore: true),
      StateError('offline'),
      _page(['m1'], hasMore: false),
    ]);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);

    await controller.load();
    await _settleController();
    await controller.loadOlderMessages('channel-1');

    expect(controller.olderMessagesError('channel-1'), isA<StateError>());
    expect(controller.canLoadOlderMessages('channel-1'), isTrue);

    await controller.loadOlderMessages('channel-1');

    expect(controller.olderMessagesError('channel-1'), isNull);
    expect(
      controller.workspace!.messagesFor('channel-1').map((item) => item.id),
      ['m1', 'm2'],
    );
  });
}

Future<void> _settleController() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

ChannelHistoryPage _page(List<String> ids, {required bool hasMore}) {
  return ChannelHistoryPage(
    history: ChannelHistory(
      channelId: 'channel-1',
      messages: ids.map(_message).toList(),
      members: const [_member],
    ),
    hasMore: hasMore,
  );
}

ChatMessage _message(String id) => ChatMessage(
  id: id,
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: id,
  sentAt: DateTime.utc(2026, 7, 23, 0, int.parse(id.substring(1))),
);

const _member = Member(
  id: 'bot-1',
  displayName: 'Flucord',
  initials: 'FL',
  role: 'Bot',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

final class _PagedRepository implements ChatRepository {
  _PagedRepository(this._results);

  final List<Object> _results;
  final List<String?> cursors = [];
  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );

  @override
  Stream<ChatRepositoryEvent> get events => const Stream.empty();

  @override
  Future<ChatWorkspace> loadWorkspace() async => ChatWorkspace(
    spaces: const [
      CommunitySpace(
        id: 'space-1',
        name: 'Forge',
        monogram: 'FO',
        colorValue: 0xff456b5a,
      ),
    ],
    channels: const [
      ConversationChannel(
        id: 'channel-1',
        spaceId: 'space-1',
        name: 'general',
        topic: 'History',
        kind: ChannelKind.text,
      ),
    ],
    members: const [_member],
    messages: const [],
    currentMemberId: 'bot-1',
  );

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) async {
    cursors.add(beforeMessageId);
    final result = _results.removeAt(0);
    if (result is Error) throw result;
    if (result is Exception) throw result;
    return result as ChannelHistoryPage;
  }

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) =>
      _delegate.loadPinnedMessages(channelId);

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      _delegate.openDirectConversation(recipientId);

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
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _delegate.saveChannelActivity(channel);

  @override
  Future<void> close() async {}
}
