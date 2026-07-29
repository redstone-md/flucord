part of 'chat_models.dart';

/// Somebody who said they are interested in an event.
///
/// Discord returns the user, and the guild member record beside it when asked,
/// so the nickname a server knows somebody by wins over their global name —
/// which is the name everybody else in that server sees.
final class GuildScheduledEventAttendee {
  const GuildScheduledEventAttendee({
    required this.userId,
    this.displayName = '',
    this.avatarUrl,
  });

  final String userId;

  /// What to call them. Falls back to the id rather than to nothing, so a row
  /// is never blank.
  final String displayName;

  final String? avatarUrl;

  String get label => displayName.isEmpty ? userId : displayName;

  @override
  bool operator ==(Object other) =>
      other is GuildScheduledEventAttendee &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarUrl);
}
