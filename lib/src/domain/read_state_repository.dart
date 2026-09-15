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

  /// Acknowledges the message request in [channelId], whichever way the
  /// account answered it: accepted and declined requests both leave the
  /// folder.
  ///
  /// This is the account-scoped read state of the request itself
  /// (`ReadStateType.messageRequests`), not the conversation's channel read
  /// state. Discord compares the newest unanswered request against the acked
  /// one to build the folder's badge, so an answer that went unrecorded would
  /// put the request straight back.
  Future<void> acknowledgeMessageRequest(String channelId);

  /// Acknowledges the notification centre of [spaceId], the badge the inbox
  /// button reads.
  ///
  /// The centre's read state is account-scoped
  /// (`ReadStateType.notificationCenter`), and Discord keys it per space, with
  /// the direct messages filed under the same pseudo-guild every DM route
  /// uses. Opening the centre is what acks it: the mentions stay listed, the
  /// badge does not.
  Future<void> acknowledgeNotificationCentre(String spaceId);

  /// Deletes every read state the 30-day collector marks.
  ///
  /// Runs once per session start, on the schedule Discord's own client keeps.
  /// Applied locally first, so the cache shrinks on the same stroke whether or
  /// not the server call lands; the next `READY` re-reads the truth.
  Future<void> collectGarbage({DateTime? now});

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
