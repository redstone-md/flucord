import 'discord_relationship.dart';
import 'discord_remote_auth.dart';
import 'friend_suggestion.dart';
import 'relationship_request.dart';

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

  /// Sends [request], with [captcha] when an earlier try asked for one.
  ///
  /// A refusal is an answer, not a failure: it comes back as a result. Only a
  /// failure to get any answer throws.
  Future<RelationshipResult> send(
    RelationshipRequest request, {
    DiscordCaptchaAnswer? captcha,
  });

  /// People Discord thinks the account may know, as this session was told.
  List<FriendSuggestion> get friendSuggestions;

  /// Reads them again. Unlike the graph, Discord serves a route for these.
  Future<void> loadFriendSuggestions();
}
