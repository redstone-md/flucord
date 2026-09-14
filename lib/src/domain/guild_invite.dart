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

/// What an invite resolves to before anybody joins: `GET /invites/{code}`.
///
/// The preview is what the join surface shows before the user commits, so it
/// carries exactly the fields that surface draws: the server's name, its icon
/// URL, a member count, and the channel the invite lands in.
final class InvitePreview {
  const InvitePreview({
    required this.code,
    required this.name,
    this.iconUrl,
    this.guildId,
    this.description,
    this.channelName,
    this.approximateMemberCount,
    this.bannerUrl,
  });

  final String code;

  /// The server's name, as Discord renders it.
  final String name;

  /// The server's icon URL, or null when it has none.
  final String? iconUrl;

  /// The server the invite points at, when the payload carried it.
  final String? guildId;

  /// The server's description, or null when it has none.
  final String? description;

  /// The channel the invite lands in, or null when the payload named none.
  final String? channelName;

  /// How many members the server reports, or null when not reported.
  final int? approximateMemberCount;

  /// The server's banner URL, or null when it has none.
  final String? bannerUrl;
}

/// A join, a create, or a leave was refused. The refusal kind says which
/// failure the user is looking at, so the message can be plain about it.
enum GuildAccessRefusal { invalid, expired, alreadyJoined, unknown }

/// The refusal the transport carried, with the text the surface shows.
///
/// Discord codes join refusals ("Unknown Invite", "Invite expired", and the
/// 403 the POST answers when the account is already a member), but a raw
/// status code is not something a user can read, so the transport folds the
/// three honest answers into [GuildAccessRefusal] plus a message.
final class GuildAccessException implements Exception {
  const GuildAccessException({required this.refusal, required this.message});

  final GuildAccessRefusal refusal;

  final String message;

  @override
  String toString() => message;
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
