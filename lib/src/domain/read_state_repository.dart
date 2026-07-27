import 'chat_models.dart';
import 'read_state.dart';

/// The account's read state and notification settings, as the server holds
/// them.
///
/// Unread is not a local preference. Discord stores where the account has read
/// up to, mirrors every acknowledgement to the other sessions, and hands the
/// whole thing back on the next connect — which is why this is a repository
/// with a live feed rather than a field on a cache. Only a transport holding
/// the user's own session can offer it: a bot token has no read state at all,
/// so the capability is stated on [ChatRepository] and answered honestly by
/// every transport instead of guessed from a runtime type.
abstract interface class ReadStateRepository {
  /// Emits whenever read state or notification settings change, from any
  /// source: our own acknowledgement, another session's, or a settings edit.
  Stream<ReadStateSnapshot> get updates;

  /// What is true now. Never null — an account with no read state yet is
  /// [ReadStateSnapshot.empty], not an absence.
  ReadStateSnapshot get current;

  /// Marks [channel] read up to [messageId].
  ///
  /// Applied locally at once and sent on a 3 s debounce, or immediately when
  /// the channel has mentions or [immediate] is set, matching the delay
  /// Discord's own client uses.
  Future<void> acknowledge(
    ConversationChannel channel, {
    required String messageId,
    bool immediate = false,
  });

  /// Rewinds [channel] to [messageId], leaving everything after it unread.
  ///
  /// [mentionCount] is the number of messages newer than [messageId] that
  /// mention the account; the server trusts the client's count here.
  Future<void> markUnread(
    ConversationChannel channel, {
    required String messageId,
    int mentionCount = 0,
  });

  /// Marks every channel of [spaceId] read, in one batched pass.
  Future<void> markSpaceRead(
    String spaceId,
    Iterable<ConversationChannel> channels,
  );

  /// Edits the notification settings of one space, direct messages included.
  Future<void> updateSpaceNotificationSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  );

  /// Edits one channel's override inside [spaceId]'s settings.
  Future<void> updateChannelNotificationOverride({
    required String spaceId,
    required String channelId,
    required ChannelNotificationOverridePatch patch,
  });

  /// Sends anything still on a timer, for shutdown and window-hide paths.
  Future<void> flush();
}
