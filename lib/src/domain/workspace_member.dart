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
  });

  final String id;
  final String displayName;
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
  }) => Member(
    id: id,
    displayName: displayName ?? this.displayName,
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
  );

  /// Replaces the whole presence, detail included.
  ///
  /// Separate from [copyWith] because presence is the one field whose new
  /// value is routinely "nothing is known any more": a `copyWith` that ignores
  /// a null would keep showing the activity of a user who has gone offline.
  Member withPresence(UserPresence presence) => Member(
    id: id,
    displayName: displayName,
    initials: initials,
    role: role,
    presence: presence.status,
    colorValue: colorValue,
    spaceIds: spaceIds,
    rolesBySpace: rolesBySpace,
    avatarUrl: avatarUrl,
    avatarUrlsBySpace: avatarUrlsBySpace,
    membershipsBySpace: membershipsBySpace,
    presenceDetail: presence,
  );
}
