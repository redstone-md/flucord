part of 'guild_management.dart';

/// One entry of `GET /guilds/{id}/bans`.
final class GuildBan {
  const GuildBan({
    required this.userId,
    required this.userName,
    this.globalName,
    this.avatarHash,
    this.reason,
  });

  final String userId;
  final String userName;
  final String? globalName;
  final String? avatarHash;

  /// Why the ban was issued, or `null` when it was issued without one.
  final String? reason;

  String get displayName {
    final global = globalName?.trim();
    return global == null || global.isEmpty ? userName : global;
  }
}

/// How much of a banned member's recent history Discord deletes.
///
/// These are exactly the choices the ban modal offers. Discord's default is one
/// hour, except when the ban is issued from a moderator report, where the
/// report already carries the evidence and deleting it would destroy the case.
enum BanMessageDeletion implements GuildWireEnum {
  none(0),
  lastHour(3600),
  lastSixHours(21600),
  lastTwelveHours(43200),
  lastDay(86400),
  lastThreeDays(259200),
  lastWeek(604800);

  const BanMessageDeletion(this.wireValue);

  /// `delete_message_seconds`.
  @override
  final int wireValue;

  static const standardDefault = lastHour;
  static const moderatorReportDefault = none;

  static BanMessageDeletion? fromWire(Object? value) => _byWire(values, value);
}

/// A single `PUT /guilds/{id}/bans/{userId}` or a bulk `POST .../bulk-ban`.
final class BanRequest {
  const BanRequest({
    required this.userIds,
    this.deletion = BanMessageDeletion.standardDefault,
    this.reason,
    this.moderatorReportId,
  });

  final List<String> userIds;
  final BanMessageDeletion deletion;

  /// Travels in the `X-Audit-Log-Reason` header, not the body.
  final String? reason;

  final String? moderatorReportId;

  bool get isBulk => userIds.length > 1;

  /// The single-ban body. `moderator_report_id` is omitted rather than sent as
  /// null so a plain ban does not claim to be attached to a report.
  Map<String, Object?> toSingleJson() => {
    'delete_message_seconds': deletion.wireValue,
    if (moderatorReportId != null) 'moderator_report_id': moderatorReportId,
  };

  Map<String, Object?> toBulkJson() => {
    'user_ids': userIds,
    'delete_message_seconds': deletion.wireValue,
  };
}

/// What `POST /guilds/{id}/bulk-ban` reports back.
final class BulkBanResult {
  const BulkBanResult({
    this.bannedUserIds = const [],
    this.failedUserIds = const [],
  });

  final List<String> bannedUserIds;
  final List<String> failedUserIds;

  bool get isCompleteSuccess => failedUserIds.isEmpty;
}
