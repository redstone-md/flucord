part of 'chat_controller.dart';

/// The account settings surface of whatever transport is currently connected.
///
/// Kept as an extension so the answer follows the live repository rather than
/// a copy taken when the session started: swapping transports replaces the
/// settings store too, and a controller that cached one would keep writing to
/// an account nobody is signed into any more.
extension ChatControllerUserSettings on ChatController {
  UserSettingsRepository? get userSettings => _repository.userSettings;

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
}
