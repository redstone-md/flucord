import 'dart:async';

import 'package:flucord/src/application/thread_membership_controller.dart';
import 'package:flucord/src/data/discord/discord_thread_membership_service.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model', () {
    test('shows Discord\'s count when it gave one', () {
      final capped = ThreadMembership(
        threadId: 't',
        members: const [ThreadMember(threadId: 't', userId: 'a')],
        isSelfJoined: true,
        memberCount: 140,
      );

      // The list route stops at 100; the count is the whole truth.
      expect(capped.displayCount, 140);
      expect(
        ThreadMembership(
          threadId: 't',
          members: const [ThreadMember(threadId: 't', userId: 'a')],
          isSelfJoined: false,
        ).displayCount,
        1,
      );
      expect(ThreadMembership.empty('t').displayCount, 0);
      expect(ThreadMembership.empty('t').isSelfJoined, isFalse);
    });

    test('a member compares by every field it carries', () {
      final joined = DateTime.utc(2026, 7, 27);
      const base = ThreadMember(threadId: 't', userId: 'a');
      final withTime = ThreadMember(
        threadId: 't',
        userId: 'a',
        joinedAt: joined,
      );

      expect(base, const ThreadMember(threadId: 't', userId: 'a'));
      expect(
        base.hashCode,
        const ThreadMember(threadId: 't', userId: 'a').hashCode,
      );
      expect(base == withTime, isFalse);
      expect(base == Object(), isFalse);
      expect(base.flags, 0);
      expect(base.isMuted, isFalse);
    });

    test('copyWith keeps what it is not given', () {
      final membership = ThreadMembership(
        threadId: 't',
        members: const [ThreadMember(threadId: 't', userId: 'a')],
        isSelfJoined: true,
        memberCount: 3,
      );

      // Given nothing at all, every field survives.
      final untouched = membership.copyWith();
      expect(untouched.isSelfJoined, isTrue);
      expect(untouched.memberCount, 3);
      expect(untouched.members, membership.members);

      final copy = membership.copyWith(isSelfJoined: false);

      expect(copy.threadId, 't');
      expect(copy.members, membership.members);
      expect(copy.memberCount, 3);
      expect(copy.isSelfJoined, isFalse);
    });
  });

  group('service', () {
    test('reads the members the list route returns', () async {
      final transport = _FakeTransport(
        members: [
          {
            'id': 'thread-1',
            'user_id': 'me',
            'join_timestamp': '2026-07-27T10:00:00+00:00',
            'flags': 3,
            'muted': true,
          },
          {'user_id': 'other'},
          // No user at all: skipped rather than seated as an anonymous row.
          {'flags': 1},
        ],
      );
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      addTearDown(service.close);

      final membership = await service.loadMembers('thread-1');

      expect(membership.members.map((member) => member.userId), [
        'me',
        'other',
      ]);
      expect(membership.isSelfJoined, isTrue);
      expect(membership.memberCount, 2);
      final self = membership.members.first;
      expect(self.joinedAt, DateTime.utc(2026, 7, 27, 10));
      expect(self.flags, 3);
      expect(self.isMuted, isTrue);
      // The second member inherits the thread it was listed under.
      expect(membership.members.last.threadId, 'thread-1');
      expect(service.membershipFor('thread-1'), isNotNull);
    });

    test('a join applies before the dispatch arrives', () async {
      final transport = _FakeTransport();
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      addTearDown(service.close);

      await service.joinThread('thread-1');

      expect(transport.joined, ['thread-1']);
      expect(service.membershipFor('thread-1')?.isSelfJoined, isTrue);
      expect(service.membershipFor('thread-1')?.members.single.userId, 'me');

      await service.leaveThread('thread-1');

      expect(transport.left, ['thread-1']);
      expect(service.membershipFor('thread-1')?.isSelfJoined, isFalse);
      expect(service.membershipFor('thread-1')?.members, isEmpty);
    });

    test('a join with no account known still records the state', () async {
      final service = DiscordThreadMembershipService(_FakeTransport());
      addTearDown(service.close);

      await service.joinThread('thread-1');

      expect(service.membershipFor('thread-1')?.isSelfJoined, isTrue);
      expect(service.membershipFor('thread-1')?.members, isEmpty);
    });

    test('THREAD_MEMBER_UPDATE is this account joining elsewhere', () {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);

      final membership = service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-1',
        'user_id': 'me',
        'flags': 1,
      });

      expect(membership?.isSelfJoined, isTrue);
      expect(membership?.members.single.userId, 'me');
    });

    test('THREAD_MEMBERS_UPDATE seats arrivals and drops departures', () {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);

      service.accept('THREAD_MEMBERS_UPDATE', {
        'id': 'thread-1',
        'member_count': 9,
        'added_members': [
          {'user_id': 'me'},
          {'user_id': 'other'},
          // Repeated in the same burst: listed once, not twice.
          {'user_id': 'other'},
        ],
      });

      expect(service.membershipFor('thread-1')?.isSelfJoined, isTrue);
      expect(service.membershipFor('thread-1')?.memberCount, 9);
      expect(service.membershipFor('thread-1')?.members.length, 2);

      service.accept('THREAD_MEMBERS_UPDATE', {
        'id': 'thread-1',
        'removed_member_ids': ['other'],
      });

      // Somebody else leaving must not take this account with them, and the
      // count Discord last gave stands until it gives another.
      expect(service.membershipFor('thread-1')?.isSelfJoined, isTrue);
      expect(service.membershipFor('thread-1')?.members.single.userId, 'me');
      expect(service.membershipFor('thread-1')?.memberCount, 9);

      service.accept('THREAD_MEMBERS_UPDATE', {
        'id': 'thread-1',
        'removed_member_ids': ['me'],
      });

      expect(service.membershipFor('thread-1')?.isSelfJoined, isFalse);
    });

    test('a self update with no user still records the membership', () {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);

      // Discord sends this shape when only the flags changed.
      final membership = service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-1',
        'flags': 2,
      });

      expect(membership?.isSelfJoined, isTrue);
      expect(membership?.members, isEmpty);
    });

    test('a members update with no account known leaves self alone', () {
      final service = DiscordThreadMembershipService(_FakeTransport());
      addTearDown(service.close);

      service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-1',
        'user_id': 'someone',
      });
      service.accept('THREAD_MEMBERS_UPDATE', {
        'id': 'thread-1',
        'added_members': [
          {'user_id': 'other'},
        ],
      });

      expect(service.membershipFor('thread-1')?.isSelfJoined, isTrue);
    });

    test('a thread created here already has its creator in it', () {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);

      final membership = service.accept('THREAD_CREATE', {
        'id': 'thread-1',
        'member': {'user_id': 'me', 'flags': 1},
      });

      expect(membership?.isSelfJoined, isTrue);
      // A thread somebody else made arrives without a member object, and
      // nothing is claimed about it.
      expect(service.accept('THREAD_CREATE', {'id': 'thread-2'}), isNull);
    });

    test('a deleted thread is forgotten', () {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);
      service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-1',
        'user_id': 'me',
      });

      expect(service.accept('THREAD_DELETE', {'id': 'thread-1'}), isNull);
      expect(service.membershipFor('thread-1'), isNull);
      expect(service.accept('THREAD_DELETE', const {}), isNull);
    });

    test('an unrelated or malformed dispatch changes nothing', () {
      final service = DiscordThreadMembershipService(_FakeTransport());
      addTearDown(service.close);

      expect(service.accept('MESSAGE_CREATE', const {}), isNull);
      expect(service.accept('THREAD_MEMBER_UPDATE', const {'id': ''}), isNull);
      expect(service.accept('THREAD_MEMBERS_UPDATE', const {}), isNull);
      expect(
        service.accept('THREAD_CREATE', const {'id': 't', 'member': 7}),
        isNull,
      );
      // A member object with no user id yields a membership but no rows.
      final created = service.accept('THREAD_CREATE', const {
        'id': 't',
        'member': {'flags': 1},
      });
      expect(created?.members, isEmpty);
      expect(created?.isSelfJoined, isTrue);
    });

    test('publishes every change on the stream', () async {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      final seen = <String>[];
      final subscription = service.updates.listen(
        (membership) => seen.add(membership.threadId),
      );
      addTearDown(subscription.cancel);

      await service.joinThread('thread-1');
      service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-2',
        'user_id': 'me',
      });
      await service.close();
      // Closing twice is what a repository shutdown does when it is retried.
      await service.close();

      expect(seen, ['thread-1', 'thread-2']);
      // A dispatch after close must not throw on the closed controller.
      expect(
        service.accept('THREAD_MEMBER_UPDATE', {
          'id': 'thread-3',
          'user_id': 'me',
        }),
        isNotNull,
      );
    });

    test('a malformed join timestamp is dropped, not guessed', () async {
      final transport = _FakeTransport(
        members: [
          {'user_id': 'me', 'join_timestamp': 'not a date'},
          {'user_id': 'other', 'join_timestamp': 7},
        ],
      );
      final service = DiscordThreadMembershipService(transport);
      addTearDown(service.close);

      final membership = await service.loadMembers('thread-1');

      expect(
        membership.members.every((member) => member.joinedAt == null),
        isTrue,
      );
    });
  });

  group('controller', () {
    test('a transport with no membership plane offers nothing', () async {
      final controller = ThreadMembershipController(() => null);
      addTearDown(controller.dispose);

      controller.show('thread-1');
      await controller.load();

      expect(controller.isSupported, isFalse);
      expect(await controller.join(), isFalse);
      expect(await controller.leave(), isFalse);
    });

    test('shows a thread and reads its members', () async {
      final transport = _FakeTransport(
        members: [
          {'user_id': 'me'},
        ],
      );
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      expect(controller.threadId, 'thread-1');
      expect(controller.isJoined, isTrue);
      expect(controller.memberCount, 1);
      expect(controller.isLoading, isFalse);

      // Showing the same thread again is not a second read.
      controller.show('thread-1');
      expect(transport.listed, ['thread-1']);
    });

    test('clearing the thread leaves nothing on screen', () async {
      final service = DiscordThreadMembershipService(_FakeTransport());
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);
      controller.show(null);

      expect(controller.threadId, isNull);
      expect(controller.membership, isNull);
      expect(controller.isJoined, isFalse);
      expect(controller.memberCount, 0);
    });

    test('toggles between joined and not', () async {
      final transport = _FakeTransport();
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      expect(await controller.toggle(), isTrue);
      expect(controller.isJoined, isTrue);
      expect(await controller.toggle(), isTrue);
      expect(controller.isJoined, isFalse);
      expect(transport.joined, ['thread-1']);
      expect(transport.left, ['thread-1']);
    });

    test('a rejected join is reported and leaves the state alone', () async {
      final transport = _FakeTransport(failWrites: true);
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      expect(await controller.join(), isFalse);

      expect(controller.error, isNotNull);
      expect(controller.isJoined, isFalse);
      expect(controller.isBusy, isFalse);
    });

    test('a failed read is reported without wedging the controller', () async {
      final transport = _FakeTransport(failList: true);
      final service = DiscordThreadMembershipService(transport);
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);

      // And a second attempt still runs.
      await controller.load();
      expect(transport.listed.length, 2);
    });

    test('a change to another thread does not repaint this one', () async {
      final service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      controller.addListener(() => notifications++);

      service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-9',
        'user_id': 'me',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);

      service.accept('THREAD_MEMBER_UPDATE', {
        'id': 'thread-1',
        'user_id': 'me',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('a load already in flight is not started twice', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(gate: gate);
      final service = DiscordThreadMembershipService(transport);
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading, isTrue);
      await controller.load();

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(transport.listed, ['thread-1']);
    });

    test('a second write while one is in flight is refused', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(writeGate: gate);
      final service = DiscordThreadMembershipService(transport)
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);

      final first = controller.join();
      expect(controller.isBusy, isTrue);
      expect(await controller.join(), isFalse);

      gate.complete();
      expect(await first, isTrue);
      expect(transport.joined, ['thread-1']);
    });

    test('swapping the transport rebinds the store', () async {
      var service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('me');
      final controller = ThreadMembershipController(() => service);
      addTearDown(controller.dispose);

      controller.show('thread-1');
      await Future<void>.delayed(Duration.zero);
      await controller.join();
      expect(controller.isJoined, isTrue);

      final previous = service;
      service = DiscordThreadMembershipService(_FakeTransport())
        ..setCurrentUserId('other');
      addTearDown(previous.close);
      addTearDown(() => service.close());

      // The new session has never seen this thread, so it claims nothing.
      expect(controller.isSupported, isTrue);
      expect(controller.isJoined, isFalse);
    });
  });
}

final class _FakeTransport implements DiscordThreadMembershipTransport {
  _FakeTransport({
    this.members = const [],
    this.failList = false,
    this.failWrites = false,
    this.gate,
    this.writeGate,
  });

  final List<Map<String, Object?>> members;
  final bool failList;
  final bool failWrites;
  final Completer<void>? gate;
  final Completer<void>? writeGate;
  final List<String> listed = [];
  final List<String> joined = [];
  final List<String> left = [];

  @override
  Future<List<Map<String, Object?>>> listThreadMembers(String threadId) async {
    listed.add(threadId);
    await gate?.future;
    if (failList) throw StateError('unreachable');
    return members;
  }

  @override
  Future<void> joinThread(String threadId) async {
    await writeGate?.future;
    if (failWrites) throw StateError('rejected');
    joined.add(threadId);
  }

  @override
  Future<void> leaveThread(String threadId) async {
    await writeGate?.future;
    if (failWrites) throw StateError('rejected');
    left.add(threadId);
  }
}
