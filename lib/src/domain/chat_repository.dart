import 'chat_models.dart';
import 'user_settings_repository.dart';
import 'voice_call.dart';
import 'voice_connection.dart';

enum RepositoryConnectionStatus { offline, connecting, connected, reconnecting }

sealed class ChatRepositoryEvent {
  const ChatRepositoryEvent();
}

final class MessageUpsertedEvent extends ChatRepositoryEvent {
  const MessageUpsertedEvent({
    required this.message,
    this.member,
    this.isNew = false,
    this.mentionsCurrentMember = false,
  });

  final ChatMessage message;
  final Member? member;
  final bool isNew;
  final bool mentionsCurrentMember;
}

final class MemberUpsertedEvent extends ChatRepositoryEvent {
  const MemberUpsertedEvent(this.member);

  final Member member;
}

/// Members that arrived together, such as one member-list page.
///
/// Kept distinct from [MemberUpsertedEvent] because a roster page carries up to
/// a hundred members and applying them one event at a time would rebuild the
/// workspace's member table once per member.
final class MembersUpsertedEvent extends ChatRepositoryEvent {
  const MembersUpsertedEvent(this.members);

  final List<Member> members;
}

final class MemberRemovedEvent extends ChatRepositoryEvent {
  const MemberRemovedEvent({required this.memberId, required this.spaceId});

  final String memberId;
  final String spaceId;
}

final class PresenceChangedEvent extends ChatRepositoryEvent {
  const PresenceChangedEvent({required this.memberId, required this.presence});

  final String memberId;
  final Presence presence;
}

final class TypingStartedEvent extends ChatRepositoryEvent {
  const TypingStartedEvent({required this.channelId, required this.memberId});

  final String channelId;
  final String memberId;
}

final class PinsChangedEvent extends ChatRepositoryEvent {
  const PinsChangedEvent(this.channelId);

  final String channelId;
}

final class MessageDeletedEvent extends ChatRepositoryEvent {
  const MessageDeletedEvent({required this.messageId, required this.channelId});

  final String messageId;
  final String channelId;
}

final class ChannelUpsertedEvent extends ChatRepositoryEvent {
  const ChannelUpsertedEvent(this.channel);

  final ConversationChannel channel;
}

final class CategoryUpsertedEvent extends ChatRepositoryEvent {
  const CategoryUpsertedEvent(this.category);

  final ChannelCategory category;
}

final class SpaceUpsertedEvent extends ChatRepositoryEvent {
  const SpaceUpsertedEvent(this.space);

  final CommunitySpace space;
}

final class GuildEmojisReplacedEvent extends ChatRepositoryEvent {
  const GuildEmojisReplacedEvent({required this.spaceId, required this.emojis});

  final String spaceId;
  final List<GuildEmoji> emojis;
}

final class GuildStickersReplacedEvent extends ChatRepositoryEvent {
  const GuildStickersReplacedEvent({
    required this.spaceId,
    required this.stickers,
  });

  final String spaceId;
  final List<GuildSticker> stickers;
}

final class GuildScheduledEventUpsertedEvent extends ChatRepositoryEvent {
  const GuildScheduledEventUpsertedEvent(this.event);

  final GuildScheduledEvent event;
}

final class GuildScheduledEventDeletedEvent extends ChatRepositoryEvent {
  const GuildScheduledEventDeletedEvent({
    required this.spaceId,
    required this.eventId,
  });

  final String spaceId;
  final String eventId;
}

final class ChannelDeletedEvent extends ChatRepositoryEvent {
  const ChannelDeletedEvent(this.channelId);

  final String channelId;
}

final class CategoryDeletedEvent extends ChatRepositoryEvent {
  const CategoryDeletedEvent(this.categoryId);

  final String categoryId;
}

final class RepositoryStatusChangedEvent extends ChatRepositoryEvent {
  const RepositoryStatusChangedEvent(this.status);

  final RepositoryConnectionStatus status;
}

abstract interface class ChatRepository {
  Stream<ChatRepositoryEvent> get events;

  /// The voice plane this transport can carry, or `null` when it carries none.
  ///
  /// Voice is a property of the transport, not of the account: joining a
  /// channel is a frame on the same gateway socket that already delivers
  /// messages, so only a repository holding that socket can offer it. Stating
  /// that on the contract — rather than letting callers test what class the
  /// repository happens to be — keeps the answer honest when a transport gains
  /// or loses voice, and stops a controller from silently deciding that an
  /// implementation it does not recognise has none.
  VoiceSignalingService? get voiceSignaling;

  /// The account settings this transport can read and write, or `null`.
  ///
  /// The settings blob belongs to a logged-in Discord user, and only a
  /// transport holding that user's session can fetch it or receive the
  /// dispatch that revises it. Stating the answer here — instead of letting
  /// the settings surface guess from the repository's runtime type — is what
  /// lets a bot or demo transport say honestly that it has no settings, and
  /// what will let a future transport gain them without editing every caller.
  UserSettingsRepository? get userSettings;

  /// The private-call plane this transport can carry, or `null` when it carries
  /// none.
  ///
  /// Separate from [voiceSignaling] because the two are not the same
  /// capability: a bot session holds guild voice and can never ring a DM, and
  /// only a session that owns both the gateway socket and the user's REST
  /// credentials can do calls at all. Stating it here keeps a caller from
  /// inferring the answer from the repository's runtime type.
  DirectCallService? get directCalls;

  Future<ChatWorkspace> loadWorkspace();

  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  });

  Future<ChannelHistory> loadPinnedMessages(String channelId);

  Future<DirectConversation> openDirectConversation(String recipientId);

  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  });

  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  });

  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  });

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> startTyping(String channelId);

  Future<void> saveChannelActivity(ConversationChannel channel);

  Future<void> close();
}
