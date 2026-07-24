import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_activity_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_activity.dart';
import 'package:flucord/src/domain/discord_social_call.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('retains an incoming invite and joins its returned lobby', () async {
    final gateway = _ActivityGateway();
    final controller = DiscordSocialActivityController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    gateway.emit(_event(_invite));
    expect(controller.invites, [_invite]);

    final joined = await controller.acceptInvite(_invite);

    expect(joined, isTrue);
    expect(gateway.accepted, [_invite]);
    expect(controller.invites, isEmpty);
    expect(controller.session?.lobbyId, '700');
    expect(controller.call?.isConnected, isTrue);
  });

  test('sends an activity invite only to a confirmed friend', () async {
    final gateway = _ActivityGateway();
    final controller = DiscordSocialActivityController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    expect(await controller.sendInvite(_friend), isTrue);
    expect(gateway.invitedUserIds, ['500']);
    expect(controller.session?.lobbyId, '700');
    expect(gateway.startedLobbyIds, ['700']);

    expect(
      await controller.sendInvite(
        DiscordRelationship(
          user: DiscordRelationshipUser(id: '501', displayName: 'Pending'),
          kind: DiscordRelationshipKind.incomingRequest,
        ),
      ),
      isFalse,
    );
  });

  test('invalid updates and session teardown discard ephemeral state', () {
    final gateway = _ActivityGateway();
    final controller = DiscordSocialActivityController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    gateway.emit(_event(_invite));
    gateway.emit(
      _event(
        DiscordSocialActivityInvite(
          applicationId: '100',
          parentApplicationId: '0',
          channelId: '300',
          messageId: '400',
          senderId: '500',
          partyId: 'party',
          sessionId: 'session',
          type: DiscordSocialActivityInviteType.join,
          isValid: false,
        ),
        updated: true,
      ),
    );
    expect(controller.invites, isEmpty);

    controller.reconcileSession(null, authenticated: false);
    expect(controller.canUseActivities, isFalse);
    expect(controller.session, isNull);
  });

  test(
    'controls and synchronizes voice in the joined activity lobby',
    () async {
      final gateway = _ActivityGateway();
      final controller = DiscordSocialActivityController(gateway);
      addTearDown(controller.dispose);
      controller.reconcileSession(
        DiscordSocialSdkAvailability.ready,
        authenticated: true,
      );

      expect(await controller.sendInvite(_friend), isTrue);
      expect(await controller.toggleMuted(), isTrue);
      expect(controller.call?.selfMuted, isTrue);
      expect(await controller.toggleDeafened(), isTrue);
      expect(controller.call?.selfDeafened, isTrue);

      gateway.emitCall(_callState(participants: const ['500', '501']));
      expect(controller.call?.participantUserIds, ['500', '501']);

      expect(await controller.leaveVoice(), isTrue);
      expect(controller.call?.status, DiscordSocialCallStatus.disconnected);
      controller.clearSessionNotice();
      expect(controller.session, isNull);
    },
  );

  test('keeps an invited lobby retryable when voice startup fails', () async {
    final gateway = _ActivityGateway()..failNextStart = true;
    final controller = DiscordSocialActivityController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    expect(await controller.sendInvite(_friend), isTrue);
    expect(controller.session?.lobbyId, '700');
    expect(controller.call, isNull);
    expect(controller.callError, 'activity_call_start_failed');

    expect(await controller.startVoice(), isTrue);
    expect(controller.call?.isConnected, isTrue);
    expect(controller.callError, isNull);
  });
}

final _friend = DiscordRelationship(
  user: DiscordRelationshipUser(id: '500', displayName: 'Ada'),
  kind: DiscordRelationshipKind.friend,
);

final _invite = DiscordSocialActivityInvite(
  applicationId: '100',
  parentApplicationId: '0',
  channelId: '300',
  messageId: '400',
  senderId: '500',
  partyId: 'party',
  sessionId: 'session',
  type: DiscordSocialActivityInviteType.join,
  isValid: true,
);

DiscordSocialActivityInviteEvent _event(
  DiscordSocialActivityInvite invite, {
  bool updated = false,
}) => DiscordSocialActivityInviteEvent(invite: invite, updated: updated);

final class _ActivityGateway
    implements
        DiscordSocialActivityGateway,
        DiscordSocialActivityEvents,
        DiscordSocialCallGateway,
        DiscordSocialCallEvents {
  final StreamController<DiscordSocialActivityInviteEvent> _events =
      StreamController.broadcast(sync: true);
  final List<String> invitedUserIds = [];
  final List<DiscordSocialActivityInvite> accepted = [];
  final List<String> startedLobbyIds = [];
  final StreamController<DiscordSocialCallState> _callEvents =
      StreamController.broadcast(sync: true);
  DiscordSocialCallState call = _callState();
  bool failNextStart = false;

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _events.stream;

  @override
  Stream<DiscordSocialCallState> get activityCallEvents => _callEvents.stream;

  void emit(DiscordSocialActivityInviteEvent event) => _events.add(event);
  void emitCall(DiscordSocialCallState state) => _callEvents.add(state);

  @override
  Future<DiscordSocialActivitySession> acceptActivityInvite(
    DiscordSocialActivityInvite invite,
  ) async {
    accepted.add(invite);
    return DiscordSocialActivitySession(lobbyId: '700');
  }

  @override
  Future<DiscordSocialActivitySession> sendActivityInvite(String userId) async {
    invitedUserIds.add(userId);
    return DiscordSocialActivitySession(lobbyId: '700');
  }

  @override
  Future<DiscordSocialCallState> startActivityCall(String lobbyId) async {
    startedLobbyIds.add(lobbyId);
    if (failNextStart) {
      failNextStart = false;
      throw const DiscordSocialSdkException('activity_call_start_failed');
    }
    call = _callState();
    return call;
  }

  @override
  Future<DiscordSocialCallState> setActivityCallMuted({
    required String lobbyId,
    required bool muted,
  }) async {
    call = _callState(muted: muted, deafened: call.selfDeafened);
    return call;
  }

  @override
  Future<DiscordSocialCallState> setActivityCallDeafened({
    required String lobbyId,
    required bool deafened,
  }) async {
    call = _callState(muted: call.selfMuted, deafened: deafened);
    return call;
  }

  @override
  Future<DiscordSocialCallState> leaveActivityCall(String lobbyId) async {
    call = _callState(status: DiscordSocialCallStatus.disconnected);
    return call;
  }
}

DiscordSocialCallState _callState({
  DiscordSocialCallStatus status = DiscordSocialCallStatus.connected,
  List<String> participants = const ['500'],
  bool muted = false,
  bool deafened = false,
}) => DiscordSocialCallState(
  lobbyId: '700',
  status: status,
  participantUserIds: participants,
  selfMuted: muted,
  selfDeafened: deafened,
);
