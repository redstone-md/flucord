import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_activity_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_activity.dart';
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
    implements DiscordSocialActivityGateway, DiscordSocialActivityEvents {
  final StreamController<DiscordSocialActivityInviteEvent> _events =
      StreamController.broadcast(sync: true);
  final List<String> invitedUserIds = [];
  final List<DiscordSocialActivityInvite> accepted = [];

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _events.stream;

  void emit(DiscordSocialActivityInviteEvent event) => _events.add(event);

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
}
