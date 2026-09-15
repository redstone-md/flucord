part of 'guild_management.dart';

/// A guild member as the member popover needs them.
///
/// The workspace's [Member] already carries roles and standing per space, but
/// it is a cache the roster keeps, not a read the moderator asked for: it goes
/// stale the moment another moderator acts, and a popover that offered a stale
/// nickname would send it right back as if it were fresh. This record is what
/// `GET /guilds/{id}/members/{userId}` said when the popover asked.
final class GuildMemberProfile {
  const GuildMemberProfile({
    required this.userId,
    required this.guildId,
    required this.roleIds,
    this.nickname,
    this.timeoutUntil,
  });

  final String userId;
  final String guildId;

  /// The roles the member holds. Never includes `@everyone`, which is implied.
  final List<String> roleIds;

  /// The guild nickname, or `null` when they go by their own name.
  final String? nickname;

  /// `communication_disabled_until`. Null, or in the past, means not timed out.
  final DateTime? timeoutUntil;

  bool isTimedOutAt(DateTime now) => timeoutUntil?.isAfter(now) ?? false;
}

/// The timeout lengths Discord's own member card offers, in seconds.
abstract final class MemberTimeoutChoices {
  static const seconds = [60, 300, 600, 3600, 21600, 86400, 604800];

  static String label(int value) => switch (value) {
    60 => '1 minute',
    300 => '5 minutes',
    600 => '10 minutes',
    3600 => '1 hour',
    21600 => '6 hours',
    86400 => '1 day',
    _ => '1 week',
  };
}

/// A partial `PATCH /guilds/{id}/members/{userId}`.
///
/// Same tri-state discipline as [GuildRoleEdit]: omitted means untouched, and
/// for the nullable fields an explicit null is what clears them.
final class GuildMemberEdit {
  GuildMemberEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  bool contains(String key) => _values.containsKey(key);
  Object? operator [](String key) => _values[key];

  /// The guild nickname. An explicit null removes it and restores the member's
  /// own name.
  set nickname(String? value) => _values['nick'] = value;

  /// Every role the member holds after the change. Only for callers that mean
  /// to rewrite the whole list; the single-role routes are what a popover's
  /// checkbox should use, because two moderators ticking two boxes at once
  /// would otherwise each erase the other's tick.
  set roleIds(List<String> value) => _values['roles'] = List.of(value);

  /// `communication_disabled_until`. A null lifts a timeout; a moment in the
  /// past also means "not timed out", so lifting sends the null.
  set timeoutUntil(DateTime? value) => _values['communication_disabled_until'] =
      value?.toUtc().toIso8601String();

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(_values);
}
