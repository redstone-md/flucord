import 'chat_models.dart';

/// Discord's cap on the people in a group DM, the account included.
const groupDirectMessageCapacity = 10;

/// Starting and running group DMs, and closing DMs, on a session that
/// may do so.
///
/// Only a signed-in user can: a bot cannot start a group DM on its own,
/// and a demo session has nobody to ask. A controller tests the repository
/// for this interface and hides the actions when it is missing.
abstract interface class DirectMessageManagementRepository {
  /// Starts a group DM with [recipientIds], two or more of them.
  Future<DirectConversation> createGroupDirectMessage(
    List<String> recipientIds,
  );

  /// Adds [userId] to the group DM [channelId].
  Future<void> addGroupRecipient({
    required String channelId,
    required String userId,
  });

  /// Removes [userId] from the group DM [channelId]. Only its owner may.
  Future<void> removeGroupRecipient({
    required String channelId,
    required String userId,
  });

  /// Gives the group DM [channelId] its own [name].
  Future<void> renameGroupDirectMessage(String channelId, String name);

  /// Sets the group DM's picture to [iconDataUri], an image as a data URI,
  /// or removes it with null.
  Future<void> setGroupDirectMessageIcon(String channelId, String? iconDataUri);

  /// Leaves the group DM [channelId], or closes it when it is a DM with one
  /// person. A closed DM comes back with its next message.
  Future<void> closeDirectMessage(String channelId);
}
