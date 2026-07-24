part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryDirectMessages implements ChatRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  Future<void> _wait();

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) async {
    await _wait();
    final recipient = Member(
      id: recipientId,
      displayName: 'User $recipientId',
      initials: 'U',
      role: 'Direct message',
      presence: Presence.offline,
      colorValue: 0xff59636a,
      spaceIds: const {CommunitySpace.directMessagesId},
    );
    const space = CommunitySpace.directMessages();
    final channel = ConversationChannel(
      id: 'dm-$recipientId',
      spaceId: space.id,
      name: recipient.displayName,
      topic: 'Direct message with ${recipient.displayName}',
      kind: ChannelKind.text,
      recipientId: recipient.id,
    );
    _workspace = _workspace
        .upsertSpace(space)
        .upsertMember(recipient)
        .upsertChannel(channel);
    return DirectConversation(channel: channel, recipient: recipient);
  }
}
