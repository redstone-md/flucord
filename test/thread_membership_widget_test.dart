import 'dart:async';

import 'package:flucord/src/application/thread_membership_controller.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/presentation/widgets/thread_membership_button.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a member can silence the thread, and say so again', (
    tester,
  ) async {
    final repository = _FakeRepository(
      membership: ThreadMembership(
        threadId: 'thread-1',
        members: const [],
        isSelfJoined: true,
      ),
    );
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    controller.show('thread-1');
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => ThreadMembershipButton(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('thread-mute-toggle')));
    await tester.pumpAndSettle();

    expect(repository.notificationChanges.single, ('thread-1', true));

    await tester.tap(find.byKey(const ValueKey('thread-mute-toggle')));
    await tester.pumpAndSettle();

    // It reads the held setting back, so the second tap turns it off rather
    // than asking for the same thing twice.
    expect(repository.notificationChanges.last, ('thread-1', false));
  });

  testWidgets('somebody who has not joined is offered no mute', (tester) async {
    final repository = _FakeRepository(
      membership: ThreadMembership(
        threadId: 'thread-1',
        members: const [],
        isSelfJoined: false,
      ),
    );
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    controller.show('thread-1');
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: ThreadMembershipButton(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // The setting lives on the thread member, so there is nowhere to keep it.
    expect(find.byKey(const ValueKey('thread-mute-toggle')), findsNothing);
  });

  test('muting nothing asks nothing', () async {
    final repository = _FakeRepository();
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);

    expect(await controller.setMuted(muted: true), isFalse);

    expect(repository.notificationChanges, isEmpty);
  });

  test('a failed mute is reported rather than thrown', () async {
    final repository = _FakeRepository(
      membership: ThreadMembership(
        threadId: 'thread-1',
        members: const [],
        isSelfJoined: true,
      ),
    )..failNotifications = true;
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    controller.show('thread-1');

    expect(await controller.setMuted(muted: true), isFalse);

    expect(controller.error, isA<StateError>());
    expect(controller.isBusy, isFalse);
  });

  Future<void> pump(
    WidgetTester tester,
    ThreadMembershipController controller,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => ThreadMembershipButton(controller: controller),
        ),
      ),
    ),
  );

  testWidgets('shows nothing on a transport that cannot join', (tester) async {
    final controller = ThreadMembershipController(() => null);
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('thread-membership')), findsNothing);
  });

  testWidgets('shows nothing when the channel is not a thread', (tester) async {
    final repository = _FakeRepository();
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('thread-membership')), findsNothing);
  });

  testWidgets('joins and leaves the thread on screen', (tester) async {
    final repository = _FakeRepository();
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    await pump(tester, controller);
    controller.show('thread-1');
    await tester.pumpAndSettle();

    expect(find.text('Join'), findsOne);
    expect(find.byKey(const ValueKey('thread-member-count')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('thread-membership-toggle')));
    await tester.pumpAndSettle();

    expect(repository.joined, ['thread-1']);
    expect(find.text('Leave'), findsOne);
    expect(find.text('1'), findsOne);

    await tester.tap(find.byKey(const ValueKey('thread-membership-toggle')));
    await tester.pumpAndSettle();

    expect(repository.left, ['thread-1']);
    expect(find.text('Join'), findsOne);
  });

  testWidgets('shows the count Discord reported', (tester) async {
    final repository = _FakeRepository(
      membership: ThreadMembership(
        threadId: 'thread-1',
        members: const [ThreadMember(threadId: 'thread-1', userId: 'a')],
        isSelfJoined: false,
        memberCount: 42,
      ),
    );
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    await pump(tester, controller);
    controller.show('thread-1');
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOne);
  });

  testWidgets('a refused write is shown, not swallowed', (tester) async {
    final repository = _FakeRepository(failWrites: true);
    final controller = ThreadMembershipController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    await pump(tester, controller);
    controller.show('thread-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thread-membership-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('thread-membership-error')), findsOne);
    expect(find.text('Join'), findsOne);
  });
}

final class _FakeRepository implements ThreadMembershipRepository {
  _FakeRepository({this.membership, this.failWrites = false});

  final StreamController<ThreadMembership> _updates =
      StreamController.broadcast();
  final List<String> joined = [];
  final List<String> left = [];
  final bool failWrites;

  ThreadMembership? membership;

  @override
  ThreadMembership? membershipFor(String threadId) =>
      membership?.threadId == threadId ? membership : null;

  @override
  Stream<ThreadMembership> get updates => _updates.stream;

  @override
  Future<ThreadMembership> loadMembers(String threadId) async {
    final loaded =
        membership ??
        ThreadMembership(
          threadId: threadId,
          members: const [],
          isSelfJoined: false,
        );
    return _publish(loaded);
  }

  @override
  Future<void> joinThread(String threadId) async {
    if (failWrites) throw StateError('rejected');
    joined.add(threadId);
    _publish(
      ThreadMembership(
        threadId: threadId,
        members: const [ThreadMember(threadId: 'thread-1', userId: 'me')],
        isSelfJoined: true,
      ),
    );
  }

  @override
  Future<void> leaveThread(String threadId) async {
    if (failWrites) throw StateError('rejected');
    left.add(threadId);
    _publish(
      ThreadMembership(
        threadId: threadId,
        members: const [],
        isSelfJoined: false,
      ),
    );
  }

  ThreadMembership _publish(ThreadMembership value) {
    membership = value;
    if (!_updates.isClosed) _updates.add(value);
    return value;
  }

  Future<void> close() => _updates.close();

  final List<(String, bool)> notificationChanges = [];
  bool failNotifications = false;

  @override
  Future<bool> setThreadNotifications({
    required String threadId,
    required bool muted,
    int? flags,
  }) async {
    if (failNotifications) {
      failNotifications = false;
      throw StateError('mute failed');
    }
    notificationChanges.add((threadId, muted));
    // Discord echoes nothing back for this, so the held membership is what
    // the surface reads afterwards.
    membership =
        (membership ??
                ThreadMembership(
                  threadId: threadId,
                  members: const [],
                  isSelfJoined: true,
                ))
            .copyWith(selfMuted: muted);
    return true;
  }
}
