import '../domain/family_centre.dart';
import '../domain/account_standing.dart';
import '../domain/automod_rule.dart';
import '../domain/chat_models.dart';
import '../domain/conversation_summary.dart';
import '../domain/go_live_stream.dart';
import '../domain/message_component.dart';
import '../domain/application_command.dart';
import '../domain/gif_picker.dart';
import '../domain/soundboard.dart';
import '../domain/stage_channel.dart';
import '../domain/thread_membership.dart';
import '../domain/user_profile.dart';
import '../domain/chat_repository.dart';
import '../domain/guild_management_repository.dart';
import '../domain/message_search_repository.dart';
import '../domain/moderation_repository.dart';
import '../domain/presence_repository.dart';
import '../domain/read_state_repository.dart';
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
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  @override
  StageRepository? get stages => null;

  @override
  SoundboardRepository? get soundboard => null;

  @override
  GifRepository? get gifs => null;

  @override
  ApplicationCommandRepository? get applicationCommands => null;

  @override
  MessageComponentRepository? get messageComponents => null;

  @override
  GoLiveRepository? get goLive => null;

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  DirectCallService? get directCalls => null;

  /// Nothing is connected, so there is no corpus to search.
  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  SafetyHubRepository? get safetyHub => null;

  @override
  FamilyCentreRepository? get familyCentre => null;

  @override
  PresenceService? get presence => null;

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
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) async {}

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
