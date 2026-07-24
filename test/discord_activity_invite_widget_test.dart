import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_friends_controller.dart';
import 'package:flucord/src/application/discord_social_activity_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_activity.dart';
import 'package:flucord/src/domain/discord_social_call.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_activity_invite_strip.dart';
import 'package:flucord/src/presentation/widgets/discord_friend_actions.dart';
import 'package:flucord/src/presentation/widgets/discord_friends_scope.dart';
import 'package:flucord/src/presentation/widgets/discord_social_activity_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('joins an incoming activity invite from the Friends strip', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const DiscordActivityInviteStrip()));

    harness.activityGateway.emit(_invite);
    await tester.pump();

    expect(find.textContaining('Ada invited you'), findsOneWidget);
    expect(find.textContaining('Separate from a direct call'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-activity-invite-400')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discord-activity-session-joined')),
      findsOneWidget,
    );
    expect(find.text('Activity voice connected'), findsOneWidget);
    expect(find.textContaining('1 voice participant'), findsOneWidget);

    harness.activityGateway.emit(_invite);
    await tester.pump();
    expect(find.byKey(const ValueKey('toggle-activity-mute')), findsOneWidget);
    expect(find.textContaining('Ada invited you'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toggle-activity-mute')));
    await tester.pumpAndSettle();
    expect(harness.activityGateway.call.selfMuted, isTrue);

    await tester.tap(find.byKey(const ValueKey('toggle-activity-deafen')));
    await tester.pumpAndSettle();
    expect(harness.activityGateway.call.selfDeafened, isTrue);

    await tester.tap(find.byKey(const ValueKey('leave-activity-voice')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada invited you'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismiss-activity-invite-400')));
    await tester.pump();
    expect(find.byKey(const ValueKey('start-activity-voice')), findsOneWidget);
  });

  testWidgets('sends a Flucord activity invite from friend row actions', (
    tester,
  ) async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.host(
        DiscordFriendActions(
          controller: harness.friends,
          relationship: _friend,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('discord-friend-activity-invite-500')),
    );
    await tester.pumpAndSettle();

    expect(harness.activityGateway.invitedUserIds, ['500']);
    expect(find.textContaining('Activity invite sent to Ada'), findsOneWidget);
  });
}

final class _Harness {
  _Harness(
    this.socialGateway,
    this.activityGateway,
    this.friends,
    this.activity,
  );

  static Future<_Harness> create() async {
    final socialGateway = _SocialGateway();
    final activityGateway = _ActivityGateway();
    final friends = DiscordFriendsController(socialGateway);
    final activity = DiscordSocialActivityController(activityGateway);
    friends.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    activity.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    await friends.initialize();
    return _Harness(socialGateway, activityGateway, friends, activity);
  }

  final _SocialGateway socialGateway;
  final _ActivityGateway activityGateway;
  final DiscordFriendsController friends;
  final DiscordSocialActivityController activity;

  Widget host(Widget child) => MaterialApp(
    theme: FlucordTheme.dark,
    home: DiscordFriendsScope(
      controller: friends,
      child: DiscordSocialActivityScope(
        controller: activity,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );

  void dispose() {
    friends.dispose();
    activity.dispose();
  }
}

final class _ActivityGateway
    implements
        DiscordSocialActivityGateway,
        DiscordSocialActivityEvents,
        DiscordSocialCallGateway,
        DiscordSocialCallEvents {
  final StreamController<DiscordSocialActivityInviteEvent> _events =
      StreamController.broadcast(sync: true);
  final List<String> invitedUserIds = [];
  final StreamController<DiscordSocialCallState> _callEvents =
      StreamController.broadcast(sync: true);
  DiscordSocialCallState call = _callState();

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _events.stream;

  @override
  Stream<DiscordSocialCallState> get activityCallEvents => _callEvents.stream;

  void emit(DiscordSocialActivityInvite invite) => _events.add(
    DiscordSocialActivityInviteEvent(invite: invite, updated: false),
  );

  @override
  Future<DiscordSocialActivitySession> acceptActivityInvite(
    DiscordSocialActivityInvite invite,
  ) async => DiscordSocialActivitySession(lobbyId: '700');

  @override
  Future<DiscordSocialActivitySession> sendActivityInvite(String userId) async {
    invitedUserIds.add(userId);
    return DiscordSocialActivitySession(lobbyId: '700');
  }

  @override
  Future<DiscordSocialCallState> startActivityCall(String lobbyId) async {
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
  bool muted = false,
  bool deafened = false,
}) => DiscordSocialCallState(
  lobbyId: '700',
  status: status,
  participantUserIds: const ['500'],
  selfMuted: muted,
  selfDeafened: deafened,
);

final class _SocialGateway implements DiscordSocialSdkGateway {
  @override
  Future<DiscordSocialSdkAuthentication> authorize() async =>
      DiscordSocialSdkAuthentication.ready;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => [_friend];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      DiscordSocialSdkAuthentication.ready;

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}

final _friend = DiscordRelationship(
  user: DiscordRelationshipUser(
    id: '500',
    displayName: 'Ada',
    status: DiscordPresenceStatus.online,
  ),
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
