import 'dart:async';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

final class MockChatRepository implements ChatRepository {
  MockChatRepository({this.latency = const Duration(milliseconds: 240)})
    : _workspace = _seedWorkspace();

  final Duration latency;
  ChatWorkspace _workspace;
  int _messageSequence = 100;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    await _wait();
    _events.add(
      const RepositoryStatusChangedEvent(RepositoryConnectionStatus.connected),
    );
    return _workspace;
  }

  @override
  Future<ChannelHistory> loadChannelHistory(String channelId) async {
    await _wait();
    return ChannelHistory(
      channelId: channelId,
      messages: _workspace.messagesFor(channelId),
      members: _workspace.members,
    );
  }

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  }) async {
    await _wait();
    final message = ChatMessage(
      id: 'local-${_messageSequence++}',
      channelId: channelId,
      authorId: authorId,
      body: body.trim(),
      sentAt: DateTime.now(),
      attachments: [
        for (var index = 0; index < attachments.length; index++)
          MessageAttachment(
            id: 'local-attachment-$index',
            fileName: attachments[index].name,
            url: attachments[index].path,
            size: attachments[index].size,
          ),
      ],
      reply: _replyFor(replyToMessageId),
    );
    _workspace = _workspace.copyWith(
      messages: [..._workspace.messages, message],
    );
    return message;
  }

  MessageReply? _replyFor(String? messageId) {
    if (messageId == null) return null;
    final original = _workspace.messages.firstWhere(
      (message) => message.id == messageId,
    );
    return MessageReply(
      messageId: original.id,
      authorId: original.authorId,
      body: original.body,
    );
  }

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    await _wait();
    final current = _workspace.messages.firstWhere(
      (message) => message.id == messageId && message.channelId == channelId,
    );
    final edited = current.copyWith(body: body.trim(), isEdited: true);
    _workspace = _workspace.upsertMessage(edited);
    _events.add(MessageUpsertedEvent(message: edited));
    return edited;
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _wait();
    _workspace = _workspace.removeMessage(messageId);
    _events.add(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
  }

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _setReaction(messageId, emoji, add: true);

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _setReaction(messageId, emoji, add: false);

  Future<void> _setReaction(
    String messageId,
    String emoji, {
    required bool add,
  }) async {
    await _wait();
    final message = _workspace.messages.firstWhere(
      (candidate) => candidate.id == messageId,
    );
    final reactions = [...message.reactions];
    final index = reactions.indexWhere((reaction) => reaction.key == emoji);
    if (index < 0 && add) {
      reactions.add(
        MessageReaction(emojiName: emoji, count: 1, reactedByCurrentUser: true),
      );
    } else if (index >= 0) {
      final current = reactions[index];
      final count = add ? current.count + 1 : current.count - 1;
      if (count <= 0) {
        reactions.removeAt(index);
      } else {
        reactions[index] = current.copyWith(
          count: count,
          reactedByCurrentUser: add,
        );
      }
    }
    final updated = message.copyWith(reactions: reactions);
    _workspace = _workspace.upsertMessage(updated);
    _events.add(MessageUpsertedEvent(message: updated));
  }

  @override
  Future<void> close() async {}

  Future<void> _wait() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
  }

  static ChatWorkspace _seedWorkspace() {
    const spaces = [
      CommunitySpace(
        id: 'forge',
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
      ),
      CommunitySpace(
        id: 'night',
        name: 'Night Shift',
        monogram: 'NS',
        colorValue: 0xff765341,
      ),
      CommunitySpace(
        id: 'studio',
        name: 'Signal Studio',
        monogram: 'SS',
        colorValue: 0xff5f5b76,
      ),
      CommunitySpace(
        id: 'lab',
        name: 'Home Lab',
        monogram: 'HL',
        colorValue: 0xff59636a,
      ),
    ];
    const channels = [
      ConversationChannel(
        id: 'forge-general',
        spaceId: 'forge',
        name: 'general',
        topic: 'Build notes, decisions, and the work in front of us.',
        kind: ChannelKind.text,
        unread: true,
      ),
      ConversationChannel(
        id: 'forge-design',
        spaceId: 'forge',
        name: 'design',
        topic: 'Interface details, references, and review.',
        kind: ChannelKind.text,
        mentionCount: 2,
      ),
      ConversationChannel(
        id: 'forge-native',
        spaceId: 'forge',
        name: 'native-client',
        topic: 'Flutter desktop architecture and platform integration.',
        kind: ChannelKind.text,
      ),
      ConversationChannel(
        id: 'forge-voice',
        spaceId: 'forge',
        name: 'workbench',
        topic: 'Open voice room',
        kind: ChannelKind.voice,
      ),
      ConversationChannel(
        id: 'night-ops',
        spaceId: 'night',
        name: 'operations',
        topic: 'Late deployments and incident notes.',
        kind: ChannelKind.text,
        unread: true,
      ),
      ConversationChannel(
        id: 'night-radio',
        spaceId: 'night',
        name: 'radio-room',
        topic: 'Open voice room',
        kind: ChannelKind.voice,
      ),
      ConversationChannel(
        id: 'studio-feedback',
        spaceId: 'studio',
        name: 'feedback',
        topic: 'Cuts, mixes, and focused critique.',
        kind: ChannelKind.text,
      ),
      ConversationChannel(
        id: 'lab-rack',
        spaceId: 'lab',
        name: 'server-rack',
        topic: 'Machines that refuse to die.',
        kind: ChannelKind.text,
      ),
    ];
    const members = [
      Member(
        id: 'jack',
        displayName: 'Jack',
        initials: 'JK',
        role: 'Architect',
        presence: Presence.online,
        colorValue: 0xff48745f,
      ),
      Member(
        id: 'fly',
        displayName: 'Fly',
        initials: 'FL',
        role: 'Native systems',
        presence: Presence.online,
        colorValue: 0xff835c45,
      ),
      Member(
        id: 'mira',
        displayName: 'Mira Chen',
        initials: 'MC',
        role: 'Product design',
        presence: Presence.online,
        colorValue: 0xff665f82,
      ),
      Member(
        id: 'roman',
        displayName: 'Roman Vale',
        initials: 'RV',
        role: 'Infrastructure',
        presence: Presence.idle,
        colorValue: 0xff506674,
      ),
      Member(
        id: 'lena',
        displayName: 'Lena Ortiz',
        initials: 'LO',
        role: 'Audio systems',
        presence: Presence.offline,
        colorValue: 0xff715b64,
      ),
      Member(
        id: 'omar',
        displayName: 'Omar N.',
        initials: 'ON',
        role: 'Quality',
        presence: Presence.offline,
        colorValue: 0xff5d6252,
      ),
    ];
    final now = DateTime.now();
    final messages = [
      ChatMessage(
        id: 'm1',
        channelId: 'forge-general',
        authorId: 'mira',
        body:
            'The navigation pass is ready. I kept hierarchy in the type and borders, not floating panels.',
        sentAt: now.subtract(const Duration(minutes: 44)),
      ),
      ChatMessage(
        id: 'm2',
        channelId: 'forge-general',
        authorId: 'roman',
        body:
            'Windows runner is clean. Cold start is under a second on the test machine.',
        sentAt: now.subtract(const Duration(minutes: 38)),
      ),
      ChatMessage(
        id: 'm3',
        channelId: 'forge-general',
        authorId: 'fly',
        body:
            'Good. Next tracer bullet is channel switching plus local send. Transport stays behind the repository boundary.',
        sentAt: now.subtract(const Duration(minutes: 31)),
      ),
      ChatMessage(
        id: 'm4',
        channelId: 'forge-general',
        authorId: 'jack',
        body:
            'Ship the vertical slice first. We can make it loud after it is real.',
        sentAt: now.subtract(const Duration(minutes: 18)),
      ),
      ChatMessage(
        id: 'm5',
        channelId: 'forge-design',
        authorId: 'mira',
        body:
            'The selected path should read as one continuous signal from server to channel to conversation.',
        sentAt: now.subtract(const Duration(hours: 2, minutes: 12)),
      ),
      ChatMessage(
        id: 'm6',
        channelId: 'forge-design',
        authorId: 'fly',
        body:
            'Agreed. One green accent, copper only for warnings. Everything else stays graphite.',
        sentAt: now.subtract(const Duration(hours: 1, minutes: 56)),
      ),
      ChatMessage(
        id: 'm7',
        channelId: 'forge-native',
        authorId: 'roman',
        body:
            'Repository contract is small enough to replace with WebSocket plus SQLite without touching presentation.',
        sentAt: now.subtract(const Duration(hours: 3, minutes: 8)),
      ),
      ChatMessage(
        id: 'm8',
        channelId: 'night-ops',
        authorId: 'roman',
        body:
            'Old rack node recovered. Relay clicked twice, then all checks went green.',
        sentAt: now.subtract(const Duration(minutes: 9)),
      ),
      ChatMessage(
        id: 'm9',
        channelId: 'studio-feedback',
        authorId: 'lena',
        body:
            'Uploaded the dry voice sample. No suppression or gate, so we have a useful baseline.',
        sentAt: now.subtract(const Duration(hours: 5)),
      ),
      ChatMessage(
        id: 'm10',
        channelId: 'lab-rack',
        authorId: 'jack',
        body: 'The old server is still alive. Leave the fan curve alone.',
        sentAt: now.subtract(const Duration(days: 1, minutes: 27)),
      ),
    ];
    return ChatWorkspace(
      spaces: spaces,
      channels: channels,
      members: members,
      messages: messages,
      currentMemberId: 'jack',
    );
  }
}
