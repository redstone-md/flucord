/// Somebody Discord thinks this account may know.
///
/// A suggestion is not a relationship: nobody has asked for anything yet, and
/// dismissing one is the whole of what it means to say no. It is kept apart
/// from the friend graph for that reason.
final class FriendSuggestion {
  const FriendSuggestion({
    required this.userId,
    this.displayName = '',
    this.reason = '',
    this.mutualFriendCount = 0,
    this.contactNames = const [],
  });

  final String userId;

  /// What Discord calls them. Falls back to the id so a row is never blank.
  final String displayName;

  /// Why Discord thinks so, in Discord's own words. Empty when it gave none —
  /// no reason is invented here, because the reason is the whole of what makes
  /// a suggestion answerable.
  final String reason;

  final int mutualFriendCount;

  /// The names from the account's contacts this was matched against. Discord
  /// sends these only when there are at least two, so one name cannot be
  /// singled out.
  final List<String> contactNames;

  String get label => displayName.isEmpty ? userId : displayName;

  /// One line saying why, or empty when there is nothing honest to say.
  String describeReason() {
    if (contactNames.isNotEmpty) {
      return 'In your contacts as ${contactNames.join(' and ')}';
    }
    if (mutualFriendCount > 0) {
      return '$mutualFriendCount mutual friend'
          '${mutualFriendCount == 1 ? '' : 's'}';
    }
    return reason;
  }

  @override
  bool operator ==(Object other) =>
      other is FriendSuggestion &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.reason == reason &&
      other.mutualFriendCount == mutualFriendCount &&
      other.contactNames.join(',') == contactNames.join(',');

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    reason,
    mutualFriendCount,
    contactNames.join(','),
  );
}
