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
    this.username,
    this.newPassword,
    this.password,
  });

  final String? displayName;
  final String? bio;
  final String? pronouns;
  final ProfileValue<int> accentColor;
  final ProfileImage avatar;
  final ProfileImage banner;

  /// The account name, which is not the display name: Discord gates a change
  /// to it on the password, and refuses one that is already taken.
  final String? username;

  /// What the password is being changed to.
  final String? newPassword;

  /// The current password, which Discord requires for either of the two above
  /// and for nothing else.
  ///
  /// Carried through and never held: the patch it belongs to is built for one
  /// request and dropped after it.
  final String? password;

  bool get isEmpty =>
      displayName == null &&
      bio == null &&
      pronouns == null &&
      accentColor.isUntouched &&
      avatar.isUntouched &&
      banner.isUntouched &&
      username == null &&
      newPassword == null;

  /// Whether this patch changes something Discord will not take without the
  /// password. Stated here so a caller cannot forget which fields those are.
  bool get needsPassword => username != null || newPassword != null;

  /// The request body. Only touched fields appear.
  Map<String, Object?> toJson() => {
    if (displayName != null) 'global_name': displayName,
    if (bio != null) 'bio': bio,
    if (pronouns != null) 'pronouns': pronouns,
    if (!accentColor.isUntouched) 'accent_color': accentColor.value,
    if (!avatar.isUntouched) 'avatar': avatar.dataUri,
    if (!banner.isUntouched) 'banner': banner.dataUri,
    if (username != null) 'username': username,
    if (newPassword != null) 'new_password': newPassword,
    // Sent only where Discord asks for it, so an ordinary profile edit does
    // not carry a password it has no use for.
    if (needsPassword && password != null) 'password': password,
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

/// One badge on somebody's profile, as the profile route reports it.
///
/// `id` is Discord's badge id string and `icon` is a CDN hash; both are
/// carried untouched because the badge table is Discord's own and a guessed
/// label would say something the account never earned.
final class ProfileBadge {
  const ProfileBadge({
    required this.id,
    required this.description,
    required this.icon,
    this.link,
  });

  final String id;
  final String description;
  final String icon;

  /// Where the badge points, for the handful that have somewhere to go.
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is ProfileBadge &&
      other.id == id &&
      other.description == description &&
      other.icon == icon &&
      other.link == link;

  @override
  int get hashCode => Object.hash(id, description, icon, link);
}

/// The avatar decoration somebody wears, as the profile route reports it.
///
/// `asset` is a CDN path under `avatar-decoration-decoration`, which is the
/// shape Discord's own client pastes onto the CDN root.
final class ProfileDecoration {
  const ProfileDecoration({required this.asset, this.skuId});

  final String asset;
  final String? skuId;

  @override
  bool operator ==(Object other) =>
      other is ProfileDecoration &&
      other.asset == asset &&
      other.skuId == skuId;

  @override
  int get hashCode => Object.hash(asset, skuId);
}

/// A third-party account shown on somebody's profile.
///
/// Only what the profile route hands back: the connection's type and its
/// public name. Whether it is verified is kept because the profile marks it.
final class ProfileConnection {
  const ProfileConnection({
    required this.type,
    required this.name,
    this.verified = false,
  });

  final String type;
  final String name;
  final bool verified;

  @override
  bool operator ==(Object other) =>
      other is ProfileConnection &&
      other.type == type &&
      other.name == name &&
      other.verified == verified;

  @override
  int get hashCode => Object.hash(type, name, verified);
}

/// A server both this account and the profile's user belong to.
final class MutualServer {
  const MutualServer({required this.id, this.nickname});

  /// The guild id, which the workspace turns into a name.
  final String id;

  /// What the user is called in that server, when Discord reports one.
  final String? nickname;

  @override
  bool operator ==(Object other) =>
      other is MutualServer && other.id == id && other.nickname == nickname;

  @override
  int get hashCode => Object.hash(id, nickname);
}

/// A friend both this account and the profile's user share.
///
/// Only enough of the user object to draw a row: the id, and whichever name
/// Discord's response carries.
final class MutualFriend {
  const MutualFriend({
    required this.id,
    required this.displayName,
    this.username,
  });

  final String id;
  final String displayName;

  /// The handle, or null when the response carried none.
  final String? username;

  @override
  bool operator ==(Object other) =>
      other is MutualFriend &&
      other.id == id &&
      other.displayName == displayName &&
      other.username == username;

  @override
  int get hashCode => Object.hash(id, displayName, username);
}

/// Somebody else's profile, as the other-user profile route reports it.
///
/// Every field except the id is absent on an account that never set it or on
/// a private profile Discord redacts, so the popover falls back per section
/// rather than refusing to draw.
final class OtherUserProfile {
  const OtherUserProfile({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.discriminator = '',
    this.bio = '',
    this.pronouns = '',
    this.avatarHash,
    this.bannerHash,
    this.accentColor,
    this.decoration,
    this.badges = const [],
    this.connections = const [],
    this.mutualServers = const [],
    this.mutualFriends = const [],
  });

  final String userId;
  final String username;
  final String displayName;
  final String discriminator;
  final String bio;
  final String pronouns;
  final String? avatarHash;
  final String? bannerHash;

  /// A 24-bit RGB value, or null when the account set none.
  final int? accentColor;

  final ProfileDecoration? decoration;
  final List<ProfileBadge> badges;
  final List<ProfileConnection> connections;

  /// Servers both accounts belong to. Empty when the route was not asked for
  /// them or Discord did not return them.
  final List<MutualServer> mutualServers;

  /// Friends both accounts share. Same absence rules as [mutualServers].
  final List<MutualFriend> mutualFriends;

  String get effectiveName => displayName.isEmpty ? username : displayName;

  bool get hasLegacyDiscriminator =>
      discriminator.isNotEmpty && discriminator != '0';
}

/// Reads and writes the account's own profile.
abstract interface class UserProfileRepository {
  /// The profile as last read, or `null` before the first load.
  UserProfile? get current;

  Stream<UserProfile> get updates;

  Future<UserProfile?> load();

  /// Applies [patch] and returns the profile the server echoed back.
  Future<UserProfile?> apply(UserProfilePatch patch);

  /// Reads somebody else's profile.
  ///
  /// Null when Discord refused the read, which is an answer about the
  /// relationship rather than a fault: the route needs a mutual server, a
  /// friend link, or a pending request, and a stranger meets none of them.
  Future<OtherUserProfile?> loadProfileOf(String userId);
}
