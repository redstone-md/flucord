import 'discord_relationship.dart';

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
}
