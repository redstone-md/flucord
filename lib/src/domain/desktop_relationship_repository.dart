import 'discord_relationship.dart';
import 'friend_suggestion.dart';

/// The friend graph a signed-in desktop session is told about.
///
/// Named apart from the Social SDK's relationship surface on purpose: that one
/// belongs to a separate session with its own credentials, and the two must
/// not be mistaken for each other. The model is shared because a friend is a
/// friend either way.
abstract interface class DesktopRelationshipRepository {
  /// Everybody the account has a relationship with, requests first.
  List<DiscordRelationship> get relationships;

  /// Fires with the whole list whenever any of it changes.
  Stream<List<DiscordRelationship>> get relationshipUpdates;

  /// Sends a friend request, or accepts one already waiting.
  ///
  /// Discord spells both the same way: a request to somebody who has already
  /// asked is the acceptance. Returns whether it was taken — a request to
  /// somebody not accepting them is refused, which is an answer.
  Future<bool> addFriend(String userId);

  /// Removes a friend, declines a request, cancels one this account sent, or
  /// unblocks somebody. Discord has one route for "whatever this was, undo
  /// it", and which of the four it is depends only on what was on screen.
  Future<bool> removeRelationship(String userId);

  /// Blocks somebody, replacing whatever the relationship was.
  Future<bool> blockUser(String userId);

  /// People Discord thinks the account may know, as this session was told.
  List<FriendSuggestion> get friendSuggestions;

  /// Reads them again. Unlike the graph, Discord serves a route for these.
  Future<void> loadFriendSuggestions();

  /// Says no to one. Dismissing is the whole of saying no to a suggestion:
  /// there is no relationship to undo, because none was ever made.
  Future<bool> dismissSuggestion(String userId);
}
