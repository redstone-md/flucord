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

final class DirectConversation {
  const DirectConversation({required this.channel, required this.recipient});

  final ConversationChannel channel;
  final Member recipient;
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

/// What Discord draws beside a user's name: APP for an application, and the
/// server tag the user shows.
final class MemberTags {
  /// Tags from a payload that named the clan tag, even as null.
  const MemberTags({this.isBot = false, this.clanTag}) : knowsClanTag = true;

  /// Tags from a user object that left `primary_guild` out. Such a payload
  /// says nothing about the clan tag, so the tag already known stays.
  const MemberTags.clanTagUnsaid({this.isBot = false})
    : clanTag = null,
      knowsClanTag = false;

  static const none = MemberTags();

  final bool isBot;
  final ClanTag? clanTag;

  /// Whether [clanTag] is what the payload said, rather than a gap.
  final bool knowsClanTag;

  /// These tags laid over [known]: a clan tag the payload left out keeps the
  /// one in [known].
  MemberTags over(MemberTags known) => knowsClanTag || !known.knowsClanTag
      ? this
      : MemberTags(isBot: isBot, clanTag: known.clanTag);

  @override
  bool operator ==(Object other) =>
      other is MemberTags &&
      other.isBot == isBot &&
      other.clanTag == clanTag &&
      other.knowsClanTag == knowsClanTag;

  @override
  int get hashCode => Object.hash(isBot, clanTag, knowsClanTag);
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
    this.rolesBySpace = const {},
    this.avatarUrl,
    this.avatarUrlsBySpace = const {},
    this.membershipsBySpace = const {},
    this.presenceDetail,
    this.tags = MemberTags.none,
    this.username,
  });

  final String id;
  final String displayName;

  /// The unique handle, such as "freezz5126". Null until a user object that
  /// carries it arrives, and for a member cached before it was kept.
  final String? username;
  final String initials;
  final String role;
  final Presence presence;
  final int colorValue;
  final Set<String> spaceIds;
  final Map<String, String> rolesBySpace;
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

  String roleFor(String spaceId) => rolesBySpace[spaceId] ?? role;
  String? avatarUrlFor(String? spaceId) =>
      spaceId == null ? avatarUrl : avatarUrlsBySpace[spaceId] ?? avatarUrl;
  GuildMembership? membershipIn(String spaceId) => membershipsBySpace[spaceId];

  Member copyWith({
    String? displayName,
    String? role,
    Presence? presence,
    int? colorValue,
    Set<String>? spaceIds,
    Map<String, String>? rolesBySpace,
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
    initials: initials,
    role: role ?? this.role,
    presence: presence ?? this.presence,
    colorValue: colorValue ?? this.colorValue,
    spaceIds: spaceIds ?? this.spaceIds,
    rolesBySpace: rolesBySpace ?? this.rolesBySpace,
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
      rolesBySpace: {...rolesBySpace}..remove(spaceId),
      avatarUrlsBySpace: {...avatarUrlsBySpace}..remove(spaceId),
      membershipsBySpace: {...membershipsBySpace}..remove(spaceId),
    );
  }

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
        other.rolesBySpace,
        rolesBySpace,
      ) &&
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
