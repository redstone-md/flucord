import 'automod_rule.dart';
import 'account_standing.dart';
import 'age_verification.dart';
import 'auth_session.dart';
import 'chat_models.dart';
import 'desktop_relationship_repository.dart';
import 'multi_factor_auth.dart';
import 'family_centre.dart';
import 'guild_management_repository.dart';
import 'message_search_repository.dart';
import 'moderation_repository.dart';
import 'presence_repository.dart';
import 'read_state_repository.dart';
import 'user_settings_repository.dart';
import 'voice_call.dart';
import 'application_command.dart';
import 'message_component.dart';
import 'expression_favorites.dart';
import 'gif_picker.dart';
import 'conversation_summary.dart';
import 'go_live_stream.dart';
import 'soundboard.dart';
import 'stage_channel.dart';
import 'thread_membership.dart';
import 'user_profile.dart';
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
  final UserPresence presence;
}

/// Presences that arrived together, such as one `READY_SUPPLEMENTAL` or one
/// member-list page.
///
/// Kept distinct from [PresenceChangedEvent] for the same reason a roster page
/// is: a single supplemental payload carries a presence for every online
/// friend and every subscribed guild member, and applying them one event at a
/// time would rebuild the member table once per user.
final class PresencesChangedEvent extends ChatRepositoryEvent {
  const PresencesChangedEvent(this.presences);

  final Map<String, UserPresence> presences;
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

/// Discord moved a channel's newest-message pointer without sending the
/// message itself.
///
/// `PASSIVE_UPDATE_V2` does exactly that for guilds the client is not
/// subscribed to. Unread is a comparison against that pointer, so a client that
/// ignored the event would show a guild as fully read until it opened it.
final class ChannelLastMessageEvent extends ChatRepositoryEvent {
  const ChannelLastMessageEvent({
    required this.channelId,
    required this.messageId,
  });

  final String channelId;
  final String messageId;
}

final class ChannelDeletedEvent extends ChatRepositoryEvent {
  const ChannelDeletedEvent(this.channelId);

  final String channelId;
}

final class CategoryDeletedEvent extends ChatRepositoryEvent {
  const CategoryDeletedEvent(this.categoryId);

  final String categoryId;
}

/// A channel's locally held history, served before its refresh answers.
///
/// A transport that keeps a copy of a conversation emits this as soon as it
/// has one, so the channel is readable while the network is still being asked.
/// A transport that keeps none never emits it, and nothing about that
/// transport changes.
final class ChannelHistoryRestoredEvent extends ChatRepositoryEvent {
  const ChannelHistoryRestoredEvent({
    required this.history,
    required this.hasMore,
  });

  final ChannelHistory history;

  /// Whether the local copy knows of older messages beyond this page.
  final bool hasMore;
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

  /// The account's own profile, when this transport can read and edit it.
  ///
  /// A profile belongs to the account, not the installation, so only a
  /// transport authenticated as that account can offer one; every other
  /// repository reports null and the settings window hides the section rather
  /// than presenting an editor that cannot save.
  UserProfileRepository? get userProfile;

  /// Joining, leaving and listing a thread's members.
  ///
  /// Null on a transport with no account behind it: membership is per-account
  /// state, and a demo session has nobody to add to a thread.
  ThreadMembershipRepository? get threadMembership;

  /// Stage instances and this account's standing in them, or null on a
  /// transport with no account to put on a stage.
  StageRepository? get stages;

  /// The soundboard, or null on a transport that cannot play into a voice
  /// channel.
  SoundboardRepository? get soundboard;

  /// GIFs through Discord's provider proxy, or null on a transport that has
  /// no account to ask on behalf of.
  GifRepository? get gifs;

  /// The starred GIFs, stickers and emoji, or null on a transport with no
  /// account whose favourites they could be.
  ExpressionFavoritesRepository? get expressionFavorites;

  /// Slash commands in a channel, or null on a transport that cannot run
  /// them.
  ApplicationCommandRepository? get applicationCommands;

  /// Pressing the buttons and selects an application hangs off a message, or
  /// null where interactions cannot be sent.
  MessageComponentRepository? get messageComponents;

  /// Go Live streaming, or null on a transport that cannot open one.
  GoLiveRepository? get goLive;

  /// Conversation summaries, or null on a transport Discord never sends them
  /// to. Availability is an experiment decided per account.
  ConversationSummaryRepository? get conversationSummaries;

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

  /// The guild-administration plane this transport can carry, or `null`.
  ///
  /// Administering a guild needs a session Discord will let issue the admin
  /// routes at all — a bot token reaches most of them, an OAuth grant reaches
  /// almost none, and a demo transport reaches nothing. Answering here rather
  /// than letting the settings window infer it from the repository's runtime
  /// type is what lets it say honestly "not on this session" instead of opening
  /// a window whose every button fails.
  GuildManagementRepository? get guildManagement;

  /// The reporting and blocking plane, or `null`.
  ///
  /// Separate from [guildManagement] because they are different authorities:
  /// these are actions the signed-in account takes about itself, and a session
  /// can hold them while being able to administer no guild at all.
  ModerationRepository? get moderation;

  /// The account's own safety record, or `null` on a transport that has none.
  SafetyHubRepository? get safetyHub;

  /// The family centre, or `null` on a transport that has none.
  FamilyCentreRepository? get familyCentre;

  /// The account's signed-in sessions, or `null` on a transport with none.
  AuthSessionRepository? get authSessions;

  /// Two-factor authentication, or `null` on a transport that cannot set it.
  MultiFactorAuthRepository? get multiFactorAuth;

  /// Age verification, or `null` on a transport that offers none.
  AgeVerificationRepository? get ageVerification;

  /// The account's friend graph as this session knows it, or `null` on a
  /// transport that is never told one.
  DesktopRelationshipRepository? get relationships;

  /// The server-side search plane this transport can reach, or `null`.
  ///
  /// Searching asks Discord to walk a corpus this client never loaded, and the
  /// routes that do it answer to a signed-in user's own session. A transport
  /// without one — a demo workspace, a bot token — has no honest answer to
  /// give, and saying so here keeps the search surface from offering a query
  /// that could only ever fail.
  MessageSearchRepository? get messageSearch;

  /// The presence plane this transport can carry, or `null` when it carries
  /// none.
  ///
  /// Broadcasting a status is a frame on the same gateway socket that already
  /// delivers messages, and reading one requires the guild subscriptions that
  /// only a user session makes. A transport that has neither says so here
  /// instead of leaving the status picker to discover it by failing.
  PresenceService? get presence;

  /// The account's server-held read state, or `null` when this transport has
  /// none.
  ///
  /// Unread lives on Discord's servers, keyed to a logged-in user: a bot token
  /// has no read state at all and an OAuth grant cannot acknowledge one. Saying
  /// so on the contract is what lets the shell keep its purely local unread
  /// model for those transports while the desktop-user session defers to the
  /// server, without any caller inspecting a runtime type to find out which it
  /// is holding.
  ReadStateRepository? get readState;

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

  /// Acts on one message AutoMod flagged, from the alert about it.
  ///
  /// [channelId] is the alert channel and [messageId] the alert; Discord
  /// resolves which message tripped the rule from the alert itself, which is
  /// why deleting the offending message needs no id of its own. The guild is
  /// stated rather than derived: the route is a guild route, and a repository
  /// that looked the channel up would need a workspace it does not hold.
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
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
