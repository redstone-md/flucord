part of 'guild_management.dart';

/// One entry of `GET /guilds/{id}/invites`.
final class GuildInvite {
  const GuildInvite({
    required this.code,
    this.channelId,
    this.channelName,
    this.inviterId,
    this.inviterName,
    this.uses = 0,
    this.maxUses = 0,
    this.maxAgeSeconds = 0,
    this.temporary = false,
    this.createdAt,
  });

  final String code;
  final String? channelId;
  final String? channelName;
  final String? inviterId;
  final String? inviterName;
  final int uses;

  /// Zero means unlimited, which is Discord's encoding, not a missing value.
  final int maxUses;

  /// Zero means never expires.
  final int maxAgeSeconds;

  final bool temporary;
  final DateTime? createdAt;

  bool get neverExpires => maxAgeSeconds == 0;
  bool get hasUnlimitedUses => maxUses == 0;

  /// When the invite stops working, or `null` when it never does.
  DateTime? get expiresAt => createdAt == null || neverExpires
      ? null
      : createdAt!.add(Duration(seconds: maxAgeSeconds));

  bool isExpiredAt(DateTime now) => expiresAt?.isBefore(now) ?? false;

  String get url => 'https://discord.gg/$code';
}

/// The options `POST /channels/{id}/invites` accepts.
final class InviteOptions {
  const InviteOptions({
    this.maxAgeSeconds = 86400,
    this.maxUses = 0,
    this.temporary = false,
    this.unique = false,
    this.roleIds = const [],
  });

  /// The expiries Discord's invite dialog offers, in seconds. Zero is "never".
  static const maxAgeChoices = [1800, 3600, 21600, 43200, 86400, 604800, 0];

  /// The use caps the dialog offers. Zero is "no limit".
  static const maxUsesChoices = [0, 1, 5, 10, 25, 50, 100];

  final int maxAgeSeconds;
  final int maxUses;
  final bool temporary;
  final bool unique;
  final List<String> roleIds;

  /// `role_ids` is deleted when empty rather than sent as `[]`, matching the
  /// renderer — an empty array on this route reads as "grant no roles at all",
  /// which is not the same request as an ordinary invite.
  Map<String, Object?> toJson() => {
    'max_age': maxAgeSeconds,
    'max_uses': maxUses,
    'temporary': temporary,
    'unique': unique,
    if (roleIds.isNotEmpty) 'role_ids': roleIds,
  };
}
