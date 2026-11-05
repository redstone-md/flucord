part of 'chat_models.dart';

// The identity half of the workspace: who somebody is, and how present.
//
// Split out of `chat_models.dart` because presence turned a two-field status
// into a status enum, a member record and the projection between them, and the
// file that owns every other workspace model has no room left for all three.

/// Discord's status enum, R07's `clD`.
///
/// The first three members keep the ordinals the member cache has persisted
/// since before this client modelled anything but online/idle/offline — SQLite
/// stores the enum by index — so the newer statuses are appended rather than
/// slotted in where they would read better.
///
/// `streaming` is a presentation status only: R07 shows it being synthesised
/// during rendering and never produced by the self-presence state machine, so
/// it must not be sent in opcode 3.
enum Presence {
  online('online'),
  idle('idle'),
  offline('offline'),
  doNotDisturb('dnd'),
  streaming('streaming'),
  invisible('invisible'),
  unknown('unknown');

  const Presence(this.wireValue);

  final String wireValue;

  static Presence fromWire(Object? value) => switch (value) {
    'online' => online,
    'idle' => idle,
    'dnd' => doNotDisturb,
    'offline' => offline,
    'invisible' => invisible,
    'streaming' => streaming,
    _ => unknown,
  };

  /// Whether Discord paints this user as connected.
  ///
  /// `invisible` is deliberately excluded: the server never reports it for
  /// anybody but the account itself, and the account's own rows should read
  /// the same as everyone else sees them.
  bool get isOnline =>
      this == online ||
      this == idle ||
      this == doNotDisturb ||
      this == streaming;

  /// The four statuses a user may choose for themselves.
  static const selectable = [online, idle, doNotDisturb, invisible];

  String get label => switch (this) {
    online => 'Online',
    idle => 'Idle',
    doNotDisturb => 'Do Not Disturb',
    offline => 'Offline',
    streaming => 'Streaming',
    invisible => 'Invisible',
    unknown => 'Unknown',
  };
}

/// A DM with its recipients, as Discord hands out a private channel.
final class DirectConversation {
  const DirectConversation({required this.channel, required this.recipients});

  final ConversationChannel channel;
  final List<Member> recipients;
}

/// A server's tag that a user shows beside their name, such as "CODE".
///
/// Discord calls it the user's primary guild. Only a tag the user shows is
/// kept: a tag they turned off reads as no tag at all.
final class ClanTag {
  const ClanTag({required this.tag, required this.guildId, this.badgeUrl});

  final String tag;

  /// The server the tag belongs to.
  final String guildId;

  /// The server's small badge picture, or null when it has none.
  final String? badgeUrl;

  @override
  bool operator ==(Object other) =>
      other is ClanTag &&
      other.tag == tag &&
      other.guildId == guildId &&
      other.badgeUrl == badgeUrl;

  @override
  int get hashCode => Object.hash(tag, guildId, badgeUrl);
}

/// The colour Discord washes a nameplate's row with. The names are the
/// wire values of `collectibles.nameplate.palette`.
enum NameplatePalette {
  crimson,
  berry,
  sky,
  teal,
  forest,
  bubbleGum,
  violet,
  cobalt,
  clover,
  lemon,
  white;

  String get wireValue => this == bubbleGum ? 'bubble_gum' : name;

  /// The palette named [value], or null for `none` and for a palette this
  /// client does not know.
  static NameplatePalette? fromWire(Object? value) =>
      values.where((palette) => palette.wireValue == value).firstOrNull;
}

/// A picture somebody bought to stand behind their row in the member list
/// and the DM list.
final class Nameplate {
  const Nameplate({required this.asset, this.palette});

  /// A `collectibles.nameplate` object, which the cache stores as it is.
  /// Null for anything without an asset.
  static Nameplate? fromJson(Object? json) {
    if (json is! Map) return null;
    final asset = json['asset'];
    if (asset is! String || asset.isEmpty) return null;
    return Nameplate(
      asset: asset,
      palette: NameplatePalette.fromWire(json['palette']),
    );
  }

  Map<String, Object?> toJson() => {
    'asset': asset,
    'palette': palette?.wireValue,
  };

  /// The path under Discord's collectibles CDN, such as
  /// `nameplates/nameplates/twilight/`.
  final String asset;

  /// Null draws the picture with no wash under it.
  final NameplatePalette? palette;

  @override
  bool operator ==(Object other) =>
      other is Nameplate && other.asset == asset && other.palette == palette;

  @override
  int get hashCode => Object.hash(asset, palette);
}

/// The frame somebody wears around their avatar: `avatar_decoration_data`.
final class AvatarDecoration {
  const AvatarDecoration({required this.asset, this.skuId});

  /// An `avatar_decoration_data` object, which the cache stores as it is.
  /// Null for anything without an asset.
  static AvatarDecoration? fromJson(Object? json) {
    if (json is! Map) return null;
    final asset = json['asset'];
    if (asset is! String || asset.isEmpty) return null;
    final sku = json['sku_id'];
    return AvatarDecoration(asset: asset, skuId: sku is String ? sku : null);
  }

  Map<String, Object?> toJson() => {'asset': asset, 'sku_id': skuId};

  /// A file under the CDN's `avatar-decoration-presets`. An `a_` prefix
  /// marks an animated one.
  final String asset;
  final String? skuId;

  @override
  bool operator ==(Object other) =>
      other is AvatarDecoration && other.asset == asset && other.skuId == skuId;

  @override
  int get hashCode => Object.hash(asset, skuId);
}

/// How somebody styled their display name, as `display_name_styles` says.
/// The ids are Discord's; what this client can draw of them is decided where
/// the name is drawn.
final class NameStyle {
  const NameStyle({required this.colors, this.fontId, this.effectId});

  /// Opaque colours, in Discord's order.
  final List<int> colors;
  final int? fontId;
  final int? effectId;

  @override
  bool operator ==(Object other) =>
      other is NameStyle &&
      const ListEquality<int>().equals(other.colors, colors) &&
      other.fontId == fontId &&
      other.effectId == effectId;

  @override
  int get hashCode =>
      Object.hash(const ListEquality<int>().hash(colors), fontId, effectId);
}

/// The parts of [MemberTags] a user object can leave out.
enum TagPart { clanTag, nameplate, nameStyle, decoration }

/// What Discord draws with a user's name: APP for an application, the server
/// tag the user shows, the style of the name and the nameplate behind it,
/// and the decoration around their avatar.
final class MemberTags {
  const MemberTags({
    this.isBot = false,
    this.clanTag,
    this.nameplate,
    this.nameStyle,
    this.decoration,
    this.unsaid = const {},
  });

  static const none = MemberTags();

  final bool isBot;
  final ClanTag? clanTag;
  final Nameplate? nameplate;
  final NameStyle? nameStyle;
  final AvatarDecoration? decoration;

  /// The parts the payload left out. Such a payload says nothing about them,
  /// so the ones already known stay. A part sent as null says there is none.
  final Set<TagPart> unsaid;

  bool knows(TagPart part) => !unsaid.contains(part);

  /// These tags laid over [known]: a part the payload left out keeps the one
  /// in [known].
  ///
  /// A bot stays a bot. An account never stops being one, and a partial user
  /// object may leave `bot` out, which reads as false.
  MemberTags over(MemberTags known) {
    final bot = isBot || known.isBot;
    if (unsaid.isEmpty && bot == isBot) return this;
    return MemberTags(
      isBot: bot,
      clanTag: knows(TagPart.clanTag) ? clanTag : known.clanTag,
      nameplate: knows(TagPart.nameplate) ? nameplate : known.nameplate,
      nameStyle: knows(TagPart.nameStyle) ? nameStyle : known.nameStyle,
      decoration: knows(TagPart.decoration) ? decoration : known.decoration,
      unsaid: unsaid.intersection(known.unsaid),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MemberTags &&
      other.isBot == isBot &&
      other.clanTag == clanTag &&
      other.nameplate == nameplate &&
      other.nameStyle == nameStyle &&
      other.decoration == decoration &&
      const SetEquality<TagPart>().equals(other.unsaid, unsaid);

  @override
  int get hashCode =>
      Object.hash(isBot, clanTag, nameplate, nameStyle, decoration);
}

/// What a whole user object says about somebody, apart from presence: the
/// username and the tags. A presence carries one only when it names the
/// whole user.
final class MemberIdentity {
  const MemberIdentity({required this.username, required this.tags});

  final String username;
  final MemberTags tags;
}

final class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.role,
    required this.presence,
    required this.colorValue,
    this.spaceIds = const {},
    this.avatarUrl,
    this.avatarUrlsBySpace = const {},
    this.membershipsBySpace = const {},
    this.presenceDetail,
    this.tags = MemberTags.none,
    this.username,
  });

  final String id;

  /// Their own name, the same everywhere: the global name, or the username.
  /// A server's nickname for them is in [membershipsBySpace]; read the name a
  /// place shows with [displayNameFor].
  final String displayName;

  /// The unique handle, such as "freezz5126". Null until a user object that
  /// carries it arrives, and for a member cached before it was kept.
  final String? username;
  final String initials;

  /// What the member is outside any server's roles, such as "Discord user".
  /// Inside a server, the roles say it: see `HeldRoles.nameFor`.
  final String role;
  final Presence presence;
  final int colorValue;
  final Set<String> spaceIds;
  final String? avatarUrl;
  final Map<String, String> avatarUrlsBySpace;

  /// Per-guild standing: the role ids, screening state, timeout and member
  /// flags that permissions are computed from. Absent for a guild whose
  /// member payload this client never received.
  final Map<String, GuildMembership> membershipsBySpace;

  /// The gateway's full presence for this user, or null when none has arrived.
  ///
  /// Null and [UserPresence.offline] are different answers: the first says the
  /// client has never been told, which is the normal state for a member the
  /// roster listed before any presence frame covered them, and the second says
  /// Discord reported the user as offline. Only the second may be cached.
  final UserPresence? presenceDetail;

  final MemberTags tags;

  /// Whether this user is an application, which Discord marks with APP.
  bool get isBot => tags.isBot;

  /// The server tag shown beside the name, or null for none.
  ClanTag? get clanTag => tags.clanTag;

  /// The presence a row should render, falling back to the coarse status the
  /// member cache persists.
  UserPresence get presenceOrCoarse =>
      presenceDetail ?? UserPresence(status: presence);

  /// The name [spaceId] knows this member by: the nickname there, or else
  /// their own name. A DM, or null, is their own name.
  String displayNameFor(String? spaceId) =>
      membershipsBySpace[spaceId]?.nickname ?? displayName;

  String? avatarUrlFor(String? spaceId) =>
      spaceId == null ? avatarUrl : avatarUrlsBySpace[spaceId] ?? avatarUrl;
  GuildMembership? membershipIn(String spaceId) => membershipsBySpace[spaceId];

  Member copyWith({
    String? displayName,
    String? initials,
    String? role,
    Presence? presence,
    int? colorValue,
    Set<String>? spaceIds,
    String? avatarUrl,
    Map<String, String>? avatarUrlsBySpace,
    Map<String, GuildMembership>? membershipsBySpace,
    UserPresence? presenceDetail,
    MemberTags? tags,
    String? username,
  }) => Member(
    id: id,
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    initials: initials ?? this.initials,
    role: role ?? this.role,
    presence: presence ?? this.presence,
    colorValue: colorValue ?? this.colorValue,
    spaceIds: spaceIds ?? this.spaceIds,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    avatarUrlsBySpace: avatarUrlsBySpace ?? this.avatarUrlsBySpace,
    membershipsBySpace: membershipsBySpace ?? this.membershipsBySpace,
    presenceDetail: presenceDetail ?? this.presenceDetail,
    tags: tags ?? this.tags,
  );

  /// This member with [spaceId] gone, or null when nothing of them is left.
  ///
  /// A member who still holds another space keeps their record under it; one
  /// whose only space was this one has nothing left to show. A member with no
  /// spaces at all is kept, because an empty record is how the workspace says
  /// "we know this person, no server in common", which the direct-message
  /// surfaces rely on.
  Member? withoutSpace(String spaceId) {
    if (!spaceIds.contains(spaceId)) return this;
    final spaces = {...spaceIds}..remove(spaceId);
    if (spaces.isEmpty) return null;
    return copyWith(
      spaceIds: spaces,
      avatarUrlsBySpace: {...avatarUrlsBySpace}..remove(spaceId),
      membershipsBySpace: {...membershipsBySpace}..remove(spaceId),
    );
  }

  /// This member, as a payload maps them, laid over what is [known] of them.
  ///
  /// A payload says only part of what is known: the spaces and memberships
  /// it names, and no presence. So the spaces, avatars and memberships of
  /// [known] stay unless the payload names the same space, a known presence
  /// stays, and so do the tags and username the payload left out. A
  /// membership comes with the whole guild member, so a space it names and
  /// gives no avatar has none any more.
  Member over(Member known) => copyWith(
    spaceIds: {...known.spaceIds, ...spaceIds},
    avatarUrl: avatarUrl ?? known.avatarUrl,
    avatarUrlsBySpace: {
      for (final MapEntry(:key, :value) in known.avatarUrlsBySpace.entries)
        if (!membershipsBySpace.containsKey(key)) key: value,
      ...avatarUrlsBySpace,
    },
    membershipsBySpace: {...known.membershipsBySpace, ...membershipsBySpace},
    // A member payload carries no presence, so the mapper defaults it to
    // offline; letting that erase a presence the gateway already reported
    // would blank out every activity the moment the member is re-mapped.
    presence: presence == Presence.offline ? known.presence : presence,
    presenceDetail: presenceDetail ?? known.presenceDetail,
    tags: tags.over(known.tags),
    username: username ?? known.username,
  );

  /// Replaces the whole presence: the coarse status and the detail together.
  Member withPresence(UserPresence presence) =>
      copyWith(presence: presence.status, presenceDetail: presence);

  /// This member with what a whole user object says about them: the
  /// username, and the tags laid over the ones known.
  Member withIdentity(MemberIdentity identity) {
    final next = identity.tags.over(tags);
    return next == tags && identity.username == username
        ? this
        : copyWith(tags: next, username: identity.username);
  }

  /// Whether [withPresence] would change nothing.
  bool hasPresence(UserPresence presence) =>
      this.presence == presence.status && presenceDetail == presence;

  @override
  bool operator ==(Object other) =>
      other is Member &&
      other.id == id &&
      other.displayName == displayName &&
      other.username == username &&
      other.initials == initials &&
      other.role == role &&
      other.presence == presence &&
      other.colorValue == colorValue &&
      other.avatarUrl == avatarUrl &&
      other.presenceDetail == presenceDetail &&
      other.tags == tags &&
      const SetEquality<String>().equals(other.spaceIds, spaceIds) &&
      const MapEquality<String, String>().equals(
        other.avatarUrlsBySpace,
        avatarUrlsBySpace,
      ) &&
      const MapEquality<String, GuildMembership>().equals(
        other.membershipsBySpace,
        membershipsBySpace,
      );

  @override
  int get hashCode => Object.hash(id, displayName, presence, avatarUrl);
}
