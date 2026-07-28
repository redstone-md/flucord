part of 'chat_controller.dart';

/// The account settings surface of whatever transport is currently connected.
///
/// Kept as an extension so the answer follows the live repository rather than
/// a copy taken when the session started: swapping transports replaces the
/// settings store too, and a controller that cached one would keep writing to
/// an account nobody is signed into any more.
extension ChatControllerUserSettings on ChatController {
  UserSettingsRepository? get userSettings => _repository.userSettings;

  /// The account's own profile plane, or `null` for a transport with no
  /// account behind it. Read live for the same reason as the settings store.
  UserProfileRepository? get userProfile => _repository.userProfile;

  /// The thread-membership plane of the connected transport, or `null`.
  ThreadMembershipRepository? get threadMembership =>
      _repository.threadMembership;

  /// The stage plane of the connected transport, or `null`.
  StageRepository? get stages => _repository.stages;

  /// The soundboard plane of the connected transport, or `null`.
  SoundboardRepository? get soundboard => _repository.soundboard;

  /// The GIF proxy of the connected transport, or `null`.
  GifRepository? get gifs => _repository.gifs;

  /// The slash-command plane of the connected transport, or `null`.
  ApplicationCommandRepository? get applicationCommands =>
      _repository.applicationCommands;

  /// The component plane of the connected transport, or `null`.
  MessageComponentRepository? get messageComponents =>
      _repository.messageComponents;

  /// The Go Live plane of the connected transport, or `null`.
  GoLiveRepository? get goLive => _repository.goLive;

  /// Conversation summaries, or `null` where Discord sends none.
  ConversationSummaryRepository? get conversationSummaries =>
      _repository.conversationSummaries;

  /// Whether Flucord should stay silent about new messages.
  ///
  /// Read straight from the settings store instead of being pushed into the
  /// notification path, because the value can change from another device
  /// between one message and the next.
  bool get suppressesMessageNotifications =>
      _repository.userSettings?.current?.notifications.isQuiet ?? false;

  /// The guild-administration plane of the connected transport, or `null`.
  ///
  /// Read live for the same reason as the settings store: a session swap
  /// replaces it, and a settings window built on a cached one would be issuing
  /// writes with credentials nobody is signed in with any more.
  GuildManagementRepository? get guildManagement => _repository.guildManagement;

  /// The reporting and blocking plane of the connected transport, or `null`.
  ModerationRepository? get moderation => _repository.moderation;

  /// The account's own safety record, or `null` where there is none.
  SafetyHubRepository? get safetyHub => _repository.safetyHub;

  /// The family centre, or `null` where there is none.
  FamilyCentreRepository? get familyCentre => _repository.familyCentre;

  /// The account's sessions, or `null` where there are none to manage.
  AuthSessionRepository? get authSessions => _repository.authSessions;

  /// Two-factor authentication, or `null` where it cannot be set.
  MultiFactorAuthRepository? get multiFactorAuth => _repository.multiFactorAuth;
}
