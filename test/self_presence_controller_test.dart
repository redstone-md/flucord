import 'dart:async';

import 'package:flucord/src/application/self_presence_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeService implements PresenceService {
  _FakeService({this.throwOnWrite = false});

  final StreamController<SelfPresence> _updates = StreamController.broadcast();
  final List<Presence> statuses = [];
  final List<String> customStatuses = [];
  final bool throwOnWrite;
  int marks = 0;

  @override
  bool canEdit = true;

  @override
  Presence chosenStatus = Presence.online;

  @override
  UserActivity? customStatus;

  @override
  SelfPresence selfPresence = const SelfPresence();

  @override
  List<UserSession> sessions = const [UserSession(sessionId: 'phone')];

  @override
  Stream<SelfPresence> get selfPresenceUpdates => _updates.stream;

  @override
  Future<void> setStatus(Presence status) async {
    if (throwOnWrite) throw StateError('offline');
    statuses.add(status);
  }

  @override
  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  }) async {
    if (throwOnWrite) throw StateError('offline');
    customStatuses.add(text);
  }

  @override
  void markActive() => marks++;

  void push(SelfPresence presence) {
    selfPresence = presence;
    _updates.add(presence);
  }

  Future<void> close() => _updates.close();
}

void main() {
  test('reads through to the bound service', () async {
    final service = _FakeService()
      ..chosenStatus = Presence.doNotDisturb
      ..selfPresence = const SelfPresence(status: Presence.idle, since: 5)
      ..customStatus = const UserActivity(
        name: 'Custom Status',
        type: ActivityType.customStatus,
        state: 'Heads down',
      );
    addTearDown(service.close);
    final controller = SelfPresenceController(() => service)..reconcile();
    addTearDown(controller.dispose);

    expect(controller.isAvailable, isTrue);
    expect(controller.canEdit, isTrue);
    expect(controller.chosenStatus, Presence.doNotDisturb);
    expect(controller.presence.since, 5);
    expect(controller.customStatus!.state, 'Heads down');
    expect(controller.sessions, hasLength(1));
    expect(controller.userPresence.status, Presence.idle);
    expect(
      controller.userPresence.clientStatus[ClientPlatform.desktop],
      Presence.idle,
    );
  });

  test('answers honestly for a transport with no presence plane', () {
    final controller = SelfPresenceController(() => null)..reconcile();
    addTearDown(controller.dispose);

    expect(controller.isAvailable, isFalse);
    expect(controller.canEdit, isFalse);
    expect(controller.chosenStatus, Presence.online);
    expect(controller.presence.status, Presence.online);
    expect(controller.customStatus, isNull);
    expect(controller.sessions, isEmpty);
    expect(controller.lastError, isNull);
  });

  test('rebinds only when the transport actually changed', () async {
    final first = _FakeService();
    final second = _FakeService();
    addTearDown(first.close);
    addTearDown(second.close);
    var current = first;
    var notifications = 0;
    final controller = SelfPresenceController(() => current)
      ..addListener(() => notifications++)
      ..reconcile();
    expect(notifications, 1);

    controller.reconcile();
    expect(notifications, 1);

    current = second;
    controller.reconcile();
    expect(notifications, 2);

    first.push(const SelfPresence(status: Presence.idle));
    await pumpEventQueue();
    expect(
      notifications,
      2,
      reason: 'the old transport is no longer listened to',
    );

    second.push(const SelfPresence(status: Presence.idle));
    await pumpEventQueue();
    expect(notifications, 3);
    controller.dispose();
  });

  test('forwards edits and clears the error after a good write', () async {
    final service = _FakeService();
    addTearDown(service.close);
    final controller = SelfPresenceController(() => service)..reconcile();
    addTearDown(controller.dispose);

    await controller.setStatus(Presence.idle);
    await controller.setCustomStatus(text: 'Heads down');
    controller.markActive();

    expect(service.statuses, [Presence.idle]);
    expect(service.customStatuses, ['Heads down']);
    expect(service.marks, 1);
    expect(controller.lastError, isNull);
  });

  test(
    'records why an edit failed instead of throwing at the surface',
    () async {
      final service = _FakeService(throwOnWrite: true);
      addTearDown(service.close);
      final controller = SelfPresenceController(() => service)..reconcile();
      addTearDown(controller.dispose);

      await controller.setStatus(Presence.idle);

      expect(controller.lastError, isStateError);
    },
  );

  test('an edit with no transport is a no-op', () async {
    final controller = SelfPresenceController(() => null)..reconcile();
    addTearDown(controller.dispose);

    await controller.setStatus(Presence.idle);
    await controller.setCustomStatus(text: 'x');
    controller.markActive();

    expect(controller.lastError, isNull);
  });

  test('a disposed controller stops publishing', () async {
    final service = _FakeService();
    addTearDown(service.close);
    var notifications = 0;
    final controller = SelfPresenceController(() => service)
      ..addListener(() => notifications++)
      ..reconcile();

    controller.dispose();
    service.push(const SelfPresence(status: Presence.idle));
    await pumpEventQueue();

    expect(notifications, 1);
  });
}
