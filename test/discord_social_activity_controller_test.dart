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

      gateway.emitCall(
        _callState(participants: const ['500', '501'], speaking: const ['501']),
      );
      expect(controller.call?.participantUserIds, ['500', '501']);
      expect(controller.call?.isSpeaking('501'), isTrue);

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

  test('locally mutes only a remote activity voice participant', () async {
    final gateway = _ActivityGateway();
    final controller = DiscordSocialActivityController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await controller.sendInvite(_friend);
    gateway.emitCall(
      _callState(participants: const ['900', '500'], speaking: const ['500']),
    );
    final participantMuteGate = Completer<void>();
    gateway.participantMuteGate = participantMuteGate;

    final pending = controller.toggleParticipantMuted('500');

    expect(controller.isParticipantMutePending('500'), isTrue);
    expect(controller.callPending, isFalse);
    expect(await controller.toggleParticipantMuted('500'), isFalse);
    participantMuteGate.complete();
    expect(await pending, isTrue);
    expect(controller.call?.isLocallyMuted('500'), isTrue);
    expect(controller.call?.isSpeaking('500'), isTrue);
    expect(controller.participantMuteErrorFor('500'), isNull);
    expect(gateway.participantMuteRequests, ['500:true']);

    expect(await controller.toggleParticipantMuted('500'), isTrue);
    expect(controller.call?.isLocallyMuted('500'), isFalse);
    expect(gateway.participantMuteRequests, ['500:true', '500:false']);
    expect(await controller.toggleParticipantMuted('900'), isFalse);
    expect(await controller.toggleParticipantMuted('999'), isFalse);
  });

  test(
    'keeps participant mute failures retryable and clears stale rows',
    () async {
      final gateway = _ActivityGateway()..failNextParticipantMute = true;
      final controller = DiscordSocialActivityController(gateway);
      addTearDown(controller.dispose);
      controller.reconcileSession(
        DiscordSocialSdkAvailability.ready,
        authenticated: true,
      );
      await controller.sendInvite(_friend);
      gateway.emitCall(_callState(participants: const ['900', '500']));

      expect(await controller.toggleParticipantMuted('500'), isFalse);
      expect(
        controller.participantMuteErrorFor('500'),
        'activity_participant_mute_failed',
      );
      expect(await controller.toggleParticipantMuted('500'), isTrue);
      expect(controller.participantMuteErrorFor('500'), isNull);

      gateway.failNextParticipantMute = true;
      expect(await controller.toggleParticipantMuted('500'), isFalse);
      gateway.emitCall(_callState(participants: const ['900']));
      expect(controller.participantMuteErrorFor('500'), isNull);
      expect(controller.isParticipantMutePending('500'), isFalse);
    },
  );
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
  bool failNextParticipantMute = false;
  Completer<void>? participantMuteGate;
  final List<String> participantMuteRequests = [];

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _events.stream;

  @override
  Stream<DiscordSocialCallState> get activityCallEvents => _callEvents.stream;

  void emit(DiscordSocialActivityInviteEvent event) => _events.add(event);
  void emitCall(DiscordSocialCallState state) {
    call = state;
    _callEvents.add(state);
  }

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
  Future<DiscordSocialCallState> setActivityParticipantMuted({
    required String lobbyId,
    required String userId,
    required bool muted,
  }) async {
    participantMuteRequests.add('$userId:$muted');
    if (failNextParticipantMute) {
      failNextParticipantMute = false;
      throw const DiscordSocialSdkException('activity_participant_mute_failed');
    }
    final gate = participantMuteGate;
    participantMuteGate = null;
    await gate?.future;
    final locallyMuted = call.locallyMutedUserIds.toSet();
    if (muted) {
      locallyMuted.add(userId);
    } else {
      locallyMuted.remove(userId);
    }
    call = _callState(
      status: call.status,
      participants: call.participantUserIds,
      speaking: call.speakingUserIds,
      muted: call.selfMuted,
      deafened: call.selfDeafened,
      locallyMuted: locallyMuted.toList(),
    );
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
  List<String> speaking = const [],
  bool muted = false,
  bool deafened = false,
  List<String> locallyMuted = const [],
}) => DiscordSocialCallState(
  lobbyId: '700',
  currentUserId: '900',
  status: status,
  participantUserIds: participants,
  speakingUserIds: speaking,
  locallyMutedUserIds: locallyMuted,
  selfMuted: muted,
  selfDeafened: deafened,
);
