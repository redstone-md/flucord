/// The account's own profile, as it appears to everyone else.
///
/// Distinct from [UserSettings], which is how this client behaves: a profile is
/// published, lives on the account rather than on the installation, and is read
/// back from the server after every write because Discord normalises several of
/// its fields.
final class UserProfile {
  const UserProfile({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.discriminator = '',
    this.bio = '',
    this.pronouns = '',
    this.avatarHash,
    this.bannerHash,
    this.accentColor,
  });

  final String userId;

  /// The unique handle. Changing it is a separate, password-gated flow, so it
  /// is shown but never edited here.
  final String username;

  /// The name shown in conversations. Empty means the username stands in.
  final String displayName;

  /// `0` for an account migrated to the unique-username system.
  final String discriminator;

  final String bio;
  final String pronouns;
  final String? avatarHash;
  final String? bannerHash;

  /// A 24-bit RGB value, or `null` when the avatar's own colour is used.
  final int? accentColor;

  /// What other people see as this account's name.
  String get effectiveName => displayName.isEmpty ? username : displayName;

  /// Whether the account still carries a legacy `name#1234` discriminator.
  bool get hasLegacyDiscriminator =>
      discriminator.isNotEmpty && discriminator != '0';

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? discriminator,
    String? bio,
    String? pronouns,
    String? avatarHash,
    String? bannerHash,
    int? accentColor,
  }) => UserProfile(
    userId: userId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    discriminator: discriminator ?? this.discriminator,
    bio: bio ?? this.bio,
    pronouns: pronouns ?? this.pronouns,
    avatarHash: avatarHash ?? this.avatarHash,
    bannerHash: bannerHash ?? this.bannerHash,
    accentColor: accentColor ?? this.accentColor,
  );

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.userId == userId &&
      other.username == username &&
      other.displayName == displayName &&
      other.discriminator == discriminator &&
      other.bio == bio &&
      other.pronouns == pronouns &&
      other.avatarHash == avatarHash &&
      other.bannerHash == bannerHash &&
      other.accentColor == accentColor;

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    displayName,
    discriminator,
    bio,
    pronouns,
    avatarHash,
    bannerHash,
    accentColor,
  );
}

/// Fields of a profile edit, each absent unless the user changed it.
///
/// Absence and null mean different things on this route: omitting `avatar`
/// leaves the current one, while sending null removes it. Modelling that as
/// three states — untouched, set, cleared — is what stops an unrelated save
/// from stripping an avatar the user never touched.
final class UserProfilePatch {
  const UserProfilePatch({
    this.displayName,
    this.bio,
    this.pronouns,
    this.accentColor = const ProfileValue.untouched(),
    this.avatar = const ProfileImage.untouched(),
    this.banner = const ProfileImage.untouched(),
  });

  final String? displayName;
  final String? bio;
  final String? pronouns;
  final ProfileValue<int> accentColor;
  final ProfileImage avatar;
  final ProfileImage banner;

  bool get isEmpty =>
      displayName == null &&
      bio == null &&
      pronouns == null &&
      accentColor.isUntouched &&
      avatar.isUntouched &&
      banner.isUntouched;

  /// The request body. Only touched fields appear.
  Map<String, Object?> toJson() => {
    if (displayName != null) 'global_name': displayName,
    if (bio != null) 'bio': bio,
    if (pronouns != null) 'pronouns': pronouns,
    if (!accentColor.isUntouched) 'accent_color': accentColor.value,
    if (!avatar.isUntouched) 'avatar': avatar.dataUri,
    if (!banner.isUntouched) 'banner': banner.dataUri,
  };
}

/// A field that can be left alone, set, or explicitly cleared.
final class ProfileValue<T extends Object> {
  const ProfileValue.untouched() : value = null, isUntouched = true;
  const ProfileValue.set(T this.value) : isUntouched = false;
  const ProfileValue.cleared() : value = null, isUntouched = false;

  final T? value;
  final bool isUntouched;
}

/// An image field, carried as the data URI Discord's profile routes accept.
final class ProfileImage {
  const ProfileImage.untouched() : dataUri = null, isUntouched = true;
  const ProfileImage.replaced(String this.dataUri) : isUntouched = false;
  const ProfileImage.removed() : dataUri = null, isUntouched = false;

  /// `data:image/png;base64,…`. Discord rejects a CDN hash here, so a caller
  /// that passes the current hash back would silently blank the image.
  final String? dataUri;
  final bool isUntouched;
}

/// Reads and writes the account's own profile.
abstract interface class UserProfileRepository {
  /// The profile as last read, or `null` before the first load.
  UserProfile? get current;

  Stream<UserProfile> get updates;

  Future<UserProfile?> load();

  /// Applies [patch] and returns the profile the server echoed back.
  Future<UserProfile?> apply(UserProfilePatch patch);
}
