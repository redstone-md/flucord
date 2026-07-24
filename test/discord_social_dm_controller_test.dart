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
}) => DiscordSocialDmMessage(
  id: id,
  conversationUserId: userId,
  authorId: userId,
  recipientId: 'current',
  authorDisplayName: 'Ada',
  content: content,
  sentAt: DateTime.utc(2026, 2, 22, 0, minute),
  authoredByCurrentUser: false,
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
}
