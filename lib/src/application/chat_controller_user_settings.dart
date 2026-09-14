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

  /// The account's private notes, or `null` for a transport with no account
  /// behind it. Read live for the same reason as the settings store.
  UserNotesRepository? get userNotes => _repository.userNotes;

  /// The thread-membership plane of the connected transport, or `null`.
  ThreadMembershipRepository? get threadMembership =>
      _repository.threadMembership;

  /// The stage plane of the connected transport, or `null`.
  StageRepository? get stages => _repository.stages;

  /// The soundboard plane of the connected transport, or `null`.
  SoundboardRepository? get soundboard => _repository.soundboard;

  /// The upload and delete plane for a guild's expressions, or `null`.
  GuildExpressionRepository? get expressions => _repository.expressions;

  /// The GIF proxy of the connected transport, or `null`.
  GifRepository? get gifs => _repository.gifs;

  /// The starred GIFs, stickers and emoji of the connected transport.
  ExpressionFavoritesRepository? get expressionFavorites =>
      _repository.expressionFavorites;

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

  /// The summaries the connected transport holds for [channelId], newest
  /// first. Empty on a transport Discord sends none to, which is how the
  /// strip stays absent rather than empty on those sessions.
  List<ConversationSummary> conversationSummariesFor(String channelId) =>
      conversationSummaries?.summariesFor(channelId) ?? const [];

  /// Whether Flucord should stay silent about new messages.
  ///
  /// Read straight from the settings store instead of being pushed into the
  /// notification path, because the value can change from another device
  /// between one message and the next.
  bool get suppressesMessageNotifications =>
      _repository.userSettings?.current?.notifications.isQuiet ?? false;

  /// Whether the account wants the toast a new message raises.
  ///
  /// Read straight from the settings store instead of being pushed into the
  /// notification path, because the value can change from another device
  /// between one message and the next. A transport with no settings store
  /// answers `true`, which is Discord's own default for the leaf.
  bool get showsInAppNotifications =>
      _repository
          .userSettings
          ?.current
          ?.notifications
          .showsInAppNotifications ??
      true;

  /// Whether the account allows the spoken-aloud message command.
  ///
  /// The same setting gates both halves of text-to-speech: sending one and
  /// reading an arriving one aloud. Read per message rather than captured,
  /// because another device can flip it between one message and the next.
  /// A transport with no settings store answers `true`, which is Discord's
  /// own default for the leaf.
  bool get allowsTextToSpeech =>
      _repository
          .userSettings
          ?.current
          ?.messageDisplay
          .enableTextToSpeechCommand ??
      true;

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

  /// Age verification, or `null` where none is offered.
  AgeVerificationRepository? get ageVerification => _repository.ageVerification;

  /// The account's third-party connections, or `null` where there are none
  /// to manage.
  AccountConnectionsRepository? get accountConnections =>
      _repository.accountConnections;

  /// What the account holds, or `null` where the transport reads nothing.
  AccountEntitlementsRepository? get accountEntitlements =>
      _repository.accountEntitlements;

  /// Bot and app authorisation, or `null` where the transport cannot add an
  /// app to a guild.
  AppAuthorisationRepository? get appAuthorisation =>
      _repository.appAuthorisation;

  /// The account's data package, or `null` where the transport has no
  /// account to collect one from.
  AccountDataPackageRepository? get accountDataPackage =>
      _repository.accountDataPackage;

  /// The account's friend graph, or `null` where the session is told none.
  DesktopRelationshipRepository? get relationships => _repository.relationships;
}
