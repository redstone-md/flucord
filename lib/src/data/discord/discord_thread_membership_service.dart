import 'dart:async';

import '../../domain/thread_membership.dart';

/// The REST surface thread membership needs.
abstract interface class DiscordThreadMembershipTransport {
  /// `GET /channels/{id}/thread-members`.
  Future<List<Map<String, Object?>>> listThreadMembers(String threadId);

  /// `POST /channels/{id}/thread-members/@me`.
  Future<void> joinThread(String threadId);

  /// `DELETE /channels/{id}/thread-members/@me`.
  Future<void> leaveThread(String threadId);
}

/// Thread membership over the desktop-user transport.
///
/// Membership arrives from three places that have to agree: the list route,
/// `THREAD_MEMBER_UPDATE` — which Discord sends only about this account — and
/// `THREAD_MEMBERS_UPDATE`, which reports arrivals and departures for everyone
/// and carries the authoritative count. Holding one store fed by all three is
/// what keeps a join made on another device from leaving this client showing a
/// Join button for a thread it is already in.
final class DiscordThreadMembershipService
    implements ThreadMembershipRepository {
  DiscordThreadMembershipService(this._transport);

  final DiscordThreadMembershipTransport _transport;
  final StreamController<ThreadMembership> _updates =
      StreamController.broadcast();
  final Map<String, ThreadMembership> _byThread = {};

  String? _currentUserId;

  /// The account this client is signed in as.
  ///
  /// Without it a `THREAD_MEMBERS_UPDATE` cannot tell whether the user who
  /// joined was us, so self-membership would never change from a dispatch.
  void setCurrentUserId(String? userId) => _currentUserId = userId;

  @override
  ThreadMembership? membershipFor(String threadId) => _byThread[threadId];

  @override
  Stream<ThreadMembership> get updates => _updates.stream;

  @override
  Future<ThreadMembership> loadMembers(String threadId) async {
    final payload = await _transport.listThreadMembers(threadId);
    final members = [
      for (final raw in payload) ?readMember(raw, fallbackThreadId: threadId),
    ];
    final self = _currentUserId;
    return _publish(
      ThreadMembership(
        threadId: threadId,
        members: members,
        isSelfJoined:
            self != null && members.any((member) => member.userId == self),
        memberCount: members.length,
      ),
    );
  }

  @override
  Future<void> joinThread(String threadId) async {
    await _transport.joinThread(threadId);
    // Applied locally rather than waiting for the dispatch: the button has to
    // stop offering a join the moment the route succeeded, and the dispatch
    // that follows carries the same answer.
    _publish(_selfJoinedState(threadId, joined: true));
  }

  @override
  Future<void> leaveThread(String threadId) async {
    await _transport.leaveThread(threadId);
    _publish(_selfJoinedState(threadId, joined: false));
  }

  /// Folds a gateway dispatch into the store.
  ///
  /// Returns the membership it produced, or `null` for an event this store
  /// does not answer for.
  ThreadMembership? accept(String eventName, Map<String, Object?> data) =>
      switch (eventName) {
        'THREAD_MEMBER_UPDATE' => _acceptSelfUpdate(data),
        'THREAD_MEMBERS_UPDATE' => _acceptMembersUpdate(data),
        'THREAD_MEMBER_LIST_UPDATE' => _acceptMemberList(data),
        'THREAD_CREATE' => _acceptThreadCreate(data),
        'THREAD_DELETE' => _forget(data['id']),
        _ => null,
      };

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  /// `THREAD_MEMBER_UPDATE` is only ever about this account, so it is the
  /// authoritative answer to "am I in this thread".
  ThreadMembership? _acceptSelfUpdate(Map<String, Object?> data) {
    final threadId = data['id'];
    if (threadId is! String || threadId.isEmpty) return null;
    final member = readMember(data, fallbackThreadId: threadId);
    final previous = _byThread[threadId] ?? ThreadMembership.empty(threadId);
    return _publish(
      previous.copyWith(
        isSelfJoined: true,
        members: member == null
            ? previous.members
            : _withMember(previous.members, member),
      ),
    );
  }

  ThreadMembership? _acceptMembersUpdate(Map<String, Object?> data) {
    final threadId = data['id'];
    if (threadId is! String || threadId.isEmpty) return null;
    final previous = _byThread[threadId] ?? ThreadMembership.empty(threadId);
    final added = [
      for (final raw in _objects(data['added_members']))
        ?readMember(raw, fallbackThreadId: threadId),
    ];
    final removed = {for (final id in _strings(data['removed_member_ids'])) id};
    var members = previous.members;
    for (final member in added) {
      members = _withMember(members, member);
    }
    if (removed.isNotEmpty) {
      members = members
          .where((member) => !removed.contains(member.userId))
          .toList(growable: false);
    }
    final self = _currentUserId;
    // Untouched when this account is in neither list: the event is about other
    // people, and inferring our own departure from their arrival would drop us
    // out of a thread we are still in.
    final joined = self == null
        ? previous.isSelfJoined
        : added.any((member) => member.userId == self)
        ? true
        : removed.contains(self)
        ? false
        : previous.isSelfJoined;
    return _publish(
      previous.copyWith(
        members: members,
        isSelfJoined: joined,
        memberCount: data['member_count'] is int
            ? data['member_count']! as int
            : previous.memberCount,
      ),
    );
  }

  /// The lazily-loaded roster of a thread, keyed by `thread_id` rather than
  /// `id` — it is the one thread dispatch that names the thread on a different
  /// field, because the event is about the list and not about the thread.
  ///
  /// A whole snapshot, so it replaces: somebody missing from it has left, and
  /// merging would keep them listed forever.
  ThreadMembership? _acceptMemberList(Map<String, Object?> data) {
    final threadId = data['thread_id'];
    if (threadId is! String || threadId.isEmpty) return null;
    final members = [
      for (final raw in _objects(data['members']))
        ?readMember(raw, fallbackThreadId: threadId),
    ];
    final previous = _byThread[threadId] ?? ThreadMembership.empty(threadId);
    final self = _currentUserId;
    return _publish(
      previous.copyWith(
        members: members,
        // The roster is authoritative about who is in the thread, so it is
        // also the answer about this account — but only once the account is
        // known, or an empty list would read as having left.
        isSelfJoined: self == null
            ? previous.isSelfJoined
            : members.any((member) => member.userId == self),
        memberCount: members.length,
      ),
    );
  }

  /// A thread created from this client arrives with the creator already in it,
  /// reported as a nested `member` object.
  ThreadMembership? _acceptThreadCreate(Map<String, Object?> data) {
    final threadId = data['id'];
    if (threadId is! String || threadId.isEmpty) return null;
    final raw = data['member'];
    if (raw is! Map) return null;
    final member = readMember(
      raw.cast<String, Object?>(),
      fallbackThreadId: threadId,
    );
    final previous = _byThread[threadId] ?? ThreadMembership.empty(threadId);
    return _publish(
      previous.copyWith(
        isSelfJoined: true,
        members: member == null
            ? previous.members
            : _withMember(previous.members, member),
      ),
    );
  }

  ThreadMembership? _forget(Object? threadId) {
    if (threadId is! String) return null;
    _byThread.remove(threadId);
    return null;
  }

  ThreadMembership _selfJoinedState(String threadId, {required bool joined}) {
    final previous = _byThread[threadId] ?? ThreadMembership.empty(threadId);
    final self = _currentUserId;
    if (self == null) return previous.copyWith(isSelfJoined: joined);
    final members = joined
        ? _withMember(
            previous.members,
            ThreadMember(threadId: threadId, userId: self),
          )
        : previous.members
              .where((member) => member.userId != self)
              .toList(growable: false);
    return previous.copyWith(members: members, isSelfJoined: joined);
  }

  ThreadMembership _publish(ThreadMembership membership) {
    _byThread[membership.threadId] = membership;
    if (!_updates.isClosed) _updates.add(membership);
    return membership;
  }

  /// Replaces an existing row for the same user rather than appending, so a
  /// repeated dispatch cannot list somebody twice.
  static List<ThreadMember> _withMember(
    List<ThreadMember> members,
    ThreadMember member,
  ) => [
    ...members.where((existing) => existing.userId != member.userId),
    member,
  ];

  /// Maps a thread-member payload, skipping one with no user.
  static ThreadMember? readMember(
    Map<String, Object?> payload, {
    required String fallbackThreadId,
  }) {
    final userId = payload['user_id'];
    if (userId is! String || userId.isEmpty) return null;
    final threadId = payload['id'];
    return ThreadMember(
      threadId: threadId is String && threadId.isNotEmpty
          ? threadId
          : fallbackThreadId,
      userId: userId,
      joinedAt: _timestamp(payload['join_timestamp']),
      flags: payload['flags'] is int ? payload['flags']! as int : 0,
      isMuted: payload['muted'] == true,
    );
  }

  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}
