import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_dm_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_dm.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('loads sorted conversations and bounded message history', () async {
    final gateway = _DmGateway(
      conversations: [
        _conversation('1', 'Ada', '10'),
        _conversation('2', 'Zed', '20'),
      ],
      messages: {
        '2': [_message('22', '2', minute: 2), _message('21', '2', minute: 1)],
      },
    );
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);

    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();
    await controller.loadMessages('2');

    expect(controller.state, DiscordSocialDmLoadState.ready);
    expect(controller.conversations.map((item) => item.user.id), ['2', '1']);
    expect(controller.messagesFor('2').map((item) => item.id), ['21', '22']);
    expect(gateway.messageRequests.single, (userId: '2', limit: 100));
  });

  test(
    'applies live message updates and deletions to loaded history',
    () async {
      final gateway = _DmGateway(
        conversations: [_conversation('1', 'Ada', '10')],
        messages: {
          '1': [_message('10', '1', content: 'old')],
        },
      );
      final controller = DiscordSocialDmController(gateway);
      addTearDown(controller.dispose);
      controller.reconcileSession(
        DiscordSocialSdkAvailability.ready,
        authenticated: true,
      );
      await controller.initialize();
      await controller.loadMessages('1');

      gateway.emit(
        DiscordSocialDmEvent.changed(
          DiscordSocialDmEventType.updated,
          _message('10', '1', content: 'edited'),
        ),
      );
      expect(controller.messagesFor('1').single.content, 'edited');

      gateway.emit(const DiscordSocialDmEvent.deleted('10'));
      expect(controller.messagesFor('1'), isEmpty);
    },
  );

  test('preserves message content and refreshes the conversation', () async {
    final gateway = _DmGateway(
      conversations: [_conversation('1', 'Ada', '10')],
      messages: {'1': []},
    );
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();

    final sent = await controller.sendMessage('1', '  hello  ');

    expect(sent, isTrue);
    expect(gateway.sent.single, (userId: '1', content: '  hello  '));
    expect(controller.messagesFor('1').single.content, '  hello  ');
    expect(controller.isSending('1'), isFalse);
  });

  test(
    'edits and deletes only messages authored by the current user',
    () async {
      final gateway = _DmGateway(
        conversations: [_conversation('1', 'Ada', '11')],
        messages: {
          '1': [
            _message('10', '1', content: 'mine', authoredByCurrentUser: true),
            _message('11', '1', content: 'theirs'),
          ],
        },
      );
      final controller = DiscordSocialDmController(gateway);
      addTearDown(controller.dispose);
      controller.reconcileSession(
        DiscordSocialSdkAvailability.ready,
        authenticated: true,
      );
      await controller.initialize();
      await controller.loadMessages('1');

      expect(await controller.editMessage('1', '11', 'forged'), isFalse);
      expect(await controller.editMessage('1', '10', 'edited mine'), isTrue);
      expect(controller.messagesFor('1').first.content, 'edited mine');
      expect(gateway.edited.single.messageId, '10');

      expect(await controller.deleteMessage('1', '10'), isTrue);
      expect(controller.messagesFor('1').map((message) => message.id), ['11']);
      expect(gateway.deleted.single, (userId: '1', messageId: '10'));
    },
  );

  test('retains a per-message mutation error after native rejection', () async {
    final gateway = _DmGateway(
      conversations: [_conversation('1', 'Ada', '10')],
      messages: {
        '1': [_message('10', '1', authoredByCurrentUser: true)],
      },
    )..mutationError = 'rate_limited';
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();
    await controller.loadMessages('1');

    expect(await controller.editMessage('1', '10', 'edited'), isFalse);
    expect(controller.messageActionErrorFor('10'), 'rate_limited');
    expect(controller.isMutatingMessage('10'), isFalse);
  });

  test('keeps a confirmed edit when history refresh fails', () async {
    final gateway = _DmGateway(
      conversations: [_conversation('1', 'Ada', '10')],
      messages: {
        '1': [_message('10', '1', content: 'old', authoredByCurrentUser: true)],
      },
    );
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();
    await controller.loadMessages('1');
    gateway.fetchError = 'network_down';

    expect(await controller.editMessage('1', '10', 'confirmed'), isTrue);
    expect(controller.messagesFor('1').single.content, 'confirmed');
    expect(controller.messageErrorFor('1'), 'network_down');
  });

  test('deduplicates showing-chat state and clears it on sign-out', () async {
    final gateway = _DmGateway(
      conversations: [_conversation('1', 'Ada', '10')],
      messages: const {},
    );
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();

    await controller.setShowingChat(true);
    await controller.setShowingChat(true);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: false,
    );
    await pumpEventQueue();

    expect(gateway.showingChat, [true, false]);
  });

  test('clears DM state when the Social SDK session expires', () async {
    final gateway = _DmGateway(
      conversations: [_conversation('1', 'Ada', '10')],
      messages: const {},
    );
    final controller = DiscordSocialDmController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.initialize();

    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: false,
    );

    expect(controller.state, DiscordSocialDmLoadState.authorizationRequired);
    expect(controller.conversations, isEmpty);
  });
}

DiscordSocialDmConversation _conversation(
  String id,
  String name,
  String lastMessageId,
) => DiscordSocialDmConversation(
  user: DiscordRelationshipUser(id: id, displayName: name),
  lastMessageId: lastMessageId,
);

DiscordSocialDmMessage _message(
  String id,
  String userId, {
  int minute = 0,
  String content = 'message',
  bool authoredByCurrentUser = false,
}) => DiscordSocialDmMessage(
  id: id,
  conversationUserId: userId,
  authorId: authoredByCurrentUser ? 'current' : userId,
  recipientId: authoredByCurrentUser ? userId : 'current',
  authorDisplayName: authoredByCurrentUser ? 'Jack' : 'Ada',
  content: content,
  sentAt: DateTime.utc(2026, 2, 22, 0, minute),
  authoredByCurrentUser: authoredByCurrentUser,
);

final class _DmGateway
    implements DiscordSocialDmGateway, DiscordSocialDmEvents {
  _DmGateway({required this.conversations, required this.messages});

  final List<DiscordSocialDmConversation> conversations;
  final Map<String, List<DiscordSocialDmMessage>> messages;
  final StreamController<DiscordSocialDmEvent> _events =
      StreamController.broadcast(sync: true);
  final List<({String userId, int limit})> messageRequests = [];
  final List<({String userId, String content})> sent = [];
  final List<({String userId, String messageId, String content})> edited = [];
  final List<({String userId, String messageId})> deleted = [];
  final List<bool> showingChat = [];
  String? mutationError;
  String? fetchError;

  @override
  Stream<DiscordSocialDmEvent> get socialDmEvents => _events.stream;

  void emit(DiscordSocialDmEvent event) => _events.add(event);

  @override
  Future<List<DiscordSocialDmConversation>> fetchConversations() async =>
      conversations;

  @override
  Future<List<DiscordSocialDmMessage>> fetchMessages({
    required String userId,
    int limit = 100,
  }) async {
    messageRequests.add((userId: userId, limit: limit));
    if (fetchError case final error?) throw DiscordSocialSdkException(error);
    return messages[userId] ?? const [];
  }

  @override
  Future<String> sendMessage({
    required String userId,
    required String content,
  }) async {
    sent.add((userId: userId, content: content));
    final message = DiscordSocialDmMessage(
      id: '99',
      conversationUserId: userId,
      authorId: 'current',
      recipientId: userId,
      authorDisplayName: 'Jack',
      content: content,
      sentAt: DateTime.utc(2026, 2, 22, 1),
      authoredByCurrentUser: true,
    );
    messages[userId] = [...messages[userId] ?? const [], message];
    return message.id;
  }

  @override
  Future<void> editMessage({
    required String userId,
    required String messageId,
    required String content,
  }) async {
    edited.add((userId: userId, messageId: messageId, content: content));
    if (mutationError case final error?) {
      throw DiscordSocialSdkException(error);
    }
    messages[userId] = [
      for (final message in messages[userId] ?? const [])
        if (message.id == messageId)
          DiscordSocialDmMessage(
            id: message.id,
            conversationUserId: message.conversationUserId,
            authorId: message.authorId,
            recipientId: message.recipientId,
            authorDisplayName: message.authorDisplayName,
            content: content,
            sentAt: message.sentAt,
            editedAt: DateTime.utc(2026, 2, 22, 2),
            authoredByCurrentUser: message.authoredByCurrentUser,
          )
        else
          message,
    ];
  }

  @override
  Future<void> deleteMessage({
    required String userId,
    required String messageId,
  }) async {
    deleted.add((userId: userId, messageId: messageId));
    if (mutationError case final error?) {
      throw DiscordSocialSdkException(error);
    }
    messages[userId] = List.of(
      (messages[userId] ?? const []).where(
        (message) => message.id != messageId,
      ),
    );
  }

  @override
  Future<void> setShowingChat(bool showing) async {
    showingChat.add(showing);
  }
}
