part of 'guild_management.dart';

/// What this account set for itself in one server, as
/// `GET /guilds/{id}/members/@me` answers it.
///
/// Each field is null (or empty, for the bio) where the server profile sets
/// nothing, and the account's own profile shows instead.
final class OwnServerProfile {
  const OwnServerProfile({
    required this.guildId,
    required this.userId,
    this.nickname,
    this.avatarHash,
    this.bannerHash,
    this.bio = '',
  });

  final String guildId;
  final String userId;
  final String? nickname;
  final String? avatarHash;
  final String? bannerHash;
  final String bio;
}

/// A partial `PATCH /guilds/{id}/members/@me`.
///
/// Every field has three states, as on the account's own profile: untouched
/// is left out of the body, so a save that only renames never clears an
/// image. Avatar, banner and bio need Nitro; the nickname needs
/// CHANGE_NICKNAME.
final class ServerProfileEdit {
  const ServerProfileEdit({
    this.nickname = const ProfileValue.untouched(),
    this.avatar = const ProfileImage.untouched(),
    this.banner = const ProfileImage.untouched(),
    this.bio = const ProfileValue.untouched(),
  });

  /// Cleared means "go by my own name here".
  final ProfileValue<String> nickname;
  final ProfileImage avatar;
  final ProfileImage banner;
  final ProfileValue<String> bio;

  bool get isEmpty =>
      nickname.isUntouched &&
      avatar.isUntouched &&
      banner.isUntouched &&
      bio.isUntouched;

  Map<String, Object?> toJson() => {
    if (!nickname.isUntouched) 'nick': nickname.value,
    if (!avatar.isUntouched) 'avatar': avatar.dataUri,
    if (!banner.isUntouched) 'banner': banner.dataUri,
    if (!bio.isUntouched) 'bio': bio.value,
  };
}

/// Discord refused a server profile change. [message] is what the person
/// reads.
final class ServerProfileRefusal implements Exception {
  const ServerProfileRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}
