/// One account's membership of one thread.
///
/// Distinct from a guild member: joining a thread is per-thread state that
/// decides whether the thread appears in the sidebar and whether its messages
/// notify. Discord reports it both as a REST list and as two dispatches, so it
/// is modelled once here and fed from either.
final class ThreadMember {
  const ThreadMember({
    required this.threadId,
    required this.userId,
    this.joinedAt,
    this.flags = 0,
    this.isMuted = false,
  });

  final String threadId;
  final String userId;

  /// When this account joined, or `null` when the payload omitted it.
  final DateTime? joinedAt;

  /// `ThreadMemberFlags`. Carried verbatim: Flucord reads none of the bits and
  /// inventing meanings for them would be worse than passing them through.
  final int flags;

  /// Whether the account muted this thread specifically.
  final bool isMuted;

  @override
  bool operator ==(Object other) =>
      other is ThreadMember &&
      other.threadId == threadId &&
      other.userId == userId &&
      other.joinedAt == joinedAt &&
      other.flags == flags &&
      other.isMuted == isMuted;

  @override
  int get hashCode => Object.hash(threadId, userId, joinedAt, flags, isMuted);
}

/// Who is in a thread, and whether this account is one of them.
final class ThreadMembership {
  ThreadMembership({
    required this.threadId,
    required Iterable<ThreadMember> members,
    required this.isSelfJoined,
    this.memberCount,
    bool selfMuted = false,
  }) : members = List.unmodifiable(members),
       _selfMuted = selfMuted;

  ThreadMembership.empty(this.threadId)
    : members = const [],
      isSelfJoined = false,
      memberCount = null,
      _selfMuted = false;

  final String threadId;
  final List<ThreadMember> members;

  /// Whether the signed-in account is a member.
  final bool isSelfJoined;

  /// Whether this account muted the thread. Carried on the membership rather
  /// than looked up in [members], because only the session knows which member
  /// is this account and a surface must not have to guess.
  bool get isSelfMuted => _selfMuted;

  /// Discord's own count, which can exceed [members]: the list route caps at
  /// 100 and `THREAD_MEMBERS_UPDATE` reports the total separately.
  final int? memberCount;

  final bool _selfMuted;

  /// The count worth showing: Discord's when it gave one, otherwise what is
  /// actually known.
  int get displayCount => memberCount ?? members.length;

  ThreadMembership copyWith({
    Iterable<ThreadMember>? members,
    bool? isSelfJoined,
    int? memberCount,
    bool? selfMuted,
  }) => ThreadMembership(
    threadId: threadId,
    members: members ?? this.members,
    isSelfJoined: isSelfJoined ?? this.isSelfJoined,
    memberCount: memberCount ?? this.memberCount,
    selfMuted: selfMuted ?? isSelfMuted,
  );
}

/// Joining, leaving and listing a thread's members.
abstract interface class ThreadMembershipRepository {
  /// The membership as last known, or `null` before anything arrived.
  ThreadMembership? membershipFor(String threadId);

  /// Fires whenever any thread's membership changes.
  Stream<ThreadMembership> get updates;

  /// Reads the thread's members from the server.
  Future<ThreadMembership> loadMembers(String threadId);

  /// Adds this account to the thread.
  Future<void> joinThread(String threadId);

  /// Removes this account from the thread.
  Future<void> leaveThread(String threadId);

  /// Sets how this account is notified about one thread.
  ///
  /// Joining first is not a convenience: Discord keeps these settings on the
  /// thread member, so an account that is not one has nowhere for them to be
  /// stored and the change is silently lost.
  Future<bool> setThreadNotifications({
    required String threadId,
    required bool muted,
    int? flags,
  });
}
