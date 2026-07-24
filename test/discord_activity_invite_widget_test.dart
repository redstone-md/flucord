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
    expect(find.textContaining('2 voice participants'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('show-activity-voice-participants')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('activity-voice-participant-500')),
      findsOneWidget,
    );
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toggle-activity-participant-mute-900')),
      findsNothing,
    );

    final participantMuteGate = Completer<void>();
    harness.activityGateway.participantMuteGate = participantMuteGate;
    await tester.tap(
      find.byKey(const ValueKey('toggle-activity-participant-mute-500')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('activity-participant-mute-pending-500')),
      findsOneWidget,
    );
    participantMuteGate.complete();
    await tester.pumpAndSettle();
    expect(harness.activityGateway.call.isLocallyMuted('500'), isTrue);
    expect(find.text('Speaking · Locally muted'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('toggle-activity-participant-mute-500')),
    );
    await tester.pumpAndSettle();
    expect(harness.activityGateway.call.isLocallyMuted('500'), isFalse);

    harness.activityGateway.failNextParticipantMute = true;
    await tester.tap(
      find.byKey(const ValueKey('toggle-activity-participant-mute-500')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not update local volume'), findsOneWidget);
    expect(find.byTooltip('Retry local volume change'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry local volume change'));
    await tester.pumpAndSettle();
    expect(harness.activityGateway.call.isLocallyMuted('500'), isTrue);

    harness.activityGateway.emitCall(
      _callState(participants: const ['900', '500', '999'], speaking: false),
    );
    await tester.pump();
    expect(find.text('3 participants'), findsOneWidget);
    expect(find.text('Connected'), findsNWidgets(3));
    expect(find.text('Discord user · 999'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('close-activity-voice-participants')),
    );
    await tester.pumpAndSettle();

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
  bool failNextParticipantMute = false;
  Completer<void>? participantMuteGate;

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _events.stream;

  @override
  Stream<DiscordSocialCallState> get activityCallEvents => _callEvents.stream;

  void emit(DiscordSocialActivityInvite invite) => _events.add(
    DiscordSocialActivityInviteEvent(invite: invite, updated: false),
  );

  void emitCall(DiscordSocialCallState state) {
    call = state;
    _callEvents.add(state);
  }

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
    call = _callState(
      muted: muted,
      deafened: call.selfDeafened,
      speaking: call.speakingUserIds.isNotEmpty,
    );
    return call;
  }

  @override
  Future<DiscordSocialCallState> setActivityCallDeafened({
    required String lobbyId,
    required bool deafened,
  }) async {
    call = _callState(
      muted: call.selfMuted,
      deafened: deafened,
      speaking: call.speakingUserIds.isNotEmpty,
    );
    return call;
  }

  @override
  Future<DiscordSocialCallState> setActivityParticipantMuted({
    required String lobbyId,
    required String userId,
    required bool muted,
  }) async {
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
      muted: call.selfMuted,
      deafened: call.selfDeafened,
      speaking: call.speakingUserIds.isNotEmpty,
      participants: call.participantUserIds,
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
  bool muted = false,
  bool deafened = false,
  bool speaking = true,
  List<String> participants = const ['900', '500'],
  List<String> locallyMuted = const [],
}) => DiscordSocialCallState(
  lobbyId: '700',
  currentUserId: '900',
  status: status,
  participantUserIds: participants,
  speakingUserIds: speaking ? const ['500'] : const [],
  locallyMutedUserIds: locallyMuted,
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
