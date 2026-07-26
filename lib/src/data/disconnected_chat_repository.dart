import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../domain/user_settings_repository.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';

final class DisconnectedChatRepository implements ChatRepository {
  const DisconnectedChatRepository();

  static final ChatWorkspace _workspace = ChatWorkspace(
    spaces: const [],
    channels: const [],
    members: const [],
    messages: const [],
    currentMemberId: '',
  );

  @override
  Stream<ChatRepositoryEvent> get events => const Stream.empty();

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  DirectCallService? get directCalls => null;

  @override
  Future<ChatWorkspace> loadWorkspace() async => _workspace;

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) => _reject();

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) => _reject();

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      _reject();

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _reject();

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) => _reject();

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) => _reject();

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _reject();

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _reject();

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _reject();

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _reject();

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _reject();

  @override
  Future<void> startTyping(String channelId) => _reject();

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {}

  @override
  Future<void> close() async {}

  Future<T> _reject<T>() =>
      Future<T>.error(StateError('No Discord chat transport is connected.'));
}
