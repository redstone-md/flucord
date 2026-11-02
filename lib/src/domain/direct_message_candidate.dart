import 'chat_models.dart';
import 'discord_relationship.dart';

/// Somebody a new direct message can go to.
final class DirectMessageCandidate {
  const DirectMessageCandidate({
    required this.id,
    required this.name,
    required this.isFriend,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final bool isFriend;
  final String? username;
  final String? avatarUrl;

  /// Whether [lowerCaseQuery] is part of the name or the username.
  bool matches(String lowerCaseQuery) =>
      name.toLowerCase().contains(lowerCaseQuery) ||
      (username?.toLowerCase().contains(lowerCaseQuery) ?? false);

  /// Everybody this account knows of: friends first, then the other people the
  /// workspace holds, each group by name. The account itself and anybody it
  /// blocked are left out.
  static List<DirectMessageCandidate> from({
    required Iterable<Member> members,
    required String currentMemberId,
    required Iterable<DiscordRelationship> relationships,
  }) {
    final relationshipById = {
      for (final entry in relationships) entry.user.id: entry,
    };
    final memberById = {for (final member in members) member.id: member};
    bool isBlocked(String id) =>
        relationshipById[id]?.kind == DiscordRelationshipKind.blocked;
    final friends = [
      for (final entry in relationships)
        if (entry.kind == DiscordRelationshipKind.friend)
          DirectMessageCandidate(
            id: entry.user.id,
            name: entry.user.displayName,
            isFriend: true,
            username: entry.user.username,
            avatarUrl:
                entry.user.avatarUrl ?? memberById[entry.user.id]?.avatarUrl,
          ),
    ];
    final friendIds = {for (final friend in friends) friend.id};
    final others = [
      for (final member in members)
        if (member.id != currentMemberId &&
            !friendIds.contains(member.id) &&
            !isBlocked(member.id))
          DirectMessageCandidate(
            id: member.id,
            name: member.displayName,
            isFriend: false,
            avatarUrl: member.avatarUrl,
          ),
    ];
    int byName(DirectMessageCandidate left, DirectMessageCandidate right) =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase());
    return [...friends..sort(byName), ...others..sort(byName)];
  }
}
