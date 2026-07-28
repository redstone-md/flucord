import 'dart:async';

import 'package:flucord/src/application/thread_membership_controller.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/presentation/widgets/thread_membership_button.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
