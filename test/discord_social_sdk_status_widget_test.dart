import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_friends_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_friends_scope.dart';
import 'package:flucord/src/presentation/widgets/discord_social_sdk_scope.dart';
import 'package:flucord/src/presentation/widgets/oauth_account_home.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows the absent native SDK in the Friends account home', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.sdkNotBundled,
    );
    addTearDown(harness.dispose);

    await _pumpAccountHome(tester, harness);

    expect(find.text('Discord Social SDK is not bundled'), findsOneWidget);
    expect(find.textContaining('not routed through Bot API'), findsOneWidget);
  });

  testWidgets('renders native pending, online, and offline relationships', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationships: [
        _relationship(
          id: 'request-1',
          name: 'Request',
          kind: DiscordRelationshipKind.incomingRequest,
        ),
        _relationship(
          id: 'online-1',
          name: 'Online',
          status: DiscordPresenceStatus.online,
        ),
        _relationship(id: 'offline-1', name: 'Offline'),
      ],
    );
    addTearDown(harness.dispose);

    await _pumpAccountHome(tester, harness);

    expect(
      find.byKey(const ValueKey('discord-friend-directory')),
      findsOneWidget,
    );
    expect(find.text('PENDING — 1'), findsOneWidget);
    expect(find.text('ONLINE — 1'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discord-friend-online-1')),
      findsOneWidget,
    );
    expect(find.text('Social SDK'), findsOneWidget);
    expect(find.text('Native social access is linked'), findsNothing);
  });

  testWidgets('keeps linked-package authorization distinct from loading', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationshipError: 'not_authenticated',
    );
    addTearDown(harness.dispose);

    await _pumpAccountHome(tester, harness);

    expect(
      find.byKey(const ValueKey('discord-friends-auth-required')),
      findsOneWidget,
    );
    expect(find.text('Native account authorization required'), findsOneWidget);
  });

  testWidgets('keeps long native friend identity bounded on compact width', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationships: [
        _relationship(
          id: 'compact-1',
          name: 'A very long Discord display name from the night shift',
          kind: DiscordRelationshipKind.incomingRequest,
          status: DiscordPresenceStatus.doNotDisturb,
        ),
      ],
    );
    addTearDown(harness.dispose);

    await _pumpAccountHome(tester, harness, size: const Size(420, 500));

    expect(
      find.byKey(const ValueKey('discord-friend-compact-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepts an incoming request from its native row actions', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationships: [
        _relationship(
          id: 'request-1',
          name: 'Ada',
          kind: DiscordRelationshipKind.incomingRequest,
        ),
      ],
    );
    addTearDown(harness.dispose);
    await _pumpAccountHome(tester, harness);

    await tester.tap(
      find.byKey(const ValueKey('discord-friend-accept-request-1')),
    );
    await tester.pumpAndSettle();

    expect(
      harness.gateway.mutations.single.action,
      DiscordRelationshipAction.acceptRequest,
    );
    expect(find.text('PENDING — 1'), findsNothing);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
  });

  testWidgets('confirms removal before mutating a native friendship', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationships: [_relationship(id: 'friend-1', name: 'Ada')],
    );
    addTearDown(harness.dispose);
    await _pumpAccountHome(tester, harness);

    await tester.tap(
      find.byKey(const ValueKey('discord-friend-more-friend-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Friend'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Friend Ada?'), findsOneWidget);
    expect(harness.gateway.mutations, isEmpty);
    await tester.tap(find.byKey(const ValueKey('confirm-relationship-action')));
    await tester.pumpAndSettle();

    expect(
      harness.gateway.mutations.single.action,
      DiscordRelationshipAction.removeFriend,
    );
    expect(find.byKey(const ValueKey('discord-friend-friend-1')), findsNothing);
    expect(find.byKey(const ValueKey('discord-friends-empty')), findsOneWidget);
  });

  testWidgets('retains a request row when its native action fails', (
    tester,
  ) async {
    final harness = await _harnessFor(
      DiscordSocialSdkAvailability.ready,
      relationships: [
        _relationship(
          id: 'request-1',
          name: 'Ada',
          kind: DiscordRelationshipKind.incomingRequest,
        ),
      ],
      mutationError: 'rate_limited',
    );
    addTearDown(harness.dispose);
    await _pumpAccountHome(tester, harness);

    await tester.tap(
      find.byKey(const ValueKey('discord-friend-reject-request-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discord-friend-request-1')),
      findsOneWidget,
    );
    expect(find.text('Relationship action failed · Try again'), findsOneWidget);
  });
}

Future<_ControllerHarness> _harnessFor(
  DiscordSocialSdkAvailability availability, {
  List<DiscordRelationship> relationships = const [],
  String? relationshipError,
  String? mutationError,
}) async {
  final gateway = _SocialGateway(availability, relationships, relationshipError)
    ..mutationError = mutationError;
  final social = DiscordSocialSdkController(gateway);
  final friends = DiscordFriendsController(gateway);
  await social.initialize();
  friends.reconcileAvailability(social.availability);
  await friends.initialize();
  return _ControllerHarness(social, friends, gateway);
}

Future<void> _pumpAccountHome(
  WidgetTester tester,
  _ControllerHarness harness, {
  Size size = const Size(900, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: DiscordSocialSdkScope(
        controller: harness.social,
        child: DiscordFriendsScope(
          controller: harness.friends,
          child: Scaffold(
            body: OAuthAccountHomeView(
              account: DiscordOAuthAccount(
                id: 'user-1',
                username: 'jack',
                displayName: 'Jack',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  _SocialGateway(this.availability, this.relationships, this.relationshipError);

  final DiscordSocialSdkAvailability availability;
  final List<DiscordRelationship> relationships;
  final String? relationshipError;
  final List<({String userId, DiscordRelationshipAction action})> mutations =
      [];
  String? mutationError;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      availability;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    if (relationshipError case final code?) {
      throw DiscordSocialSdkException(code);
    }
    return relationships;
  }

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {
    mutations.add((userId: userId, action: action));
    if (mutationError case final code?) throw DiscordSocialSdkException(code);
  }
}

final class _ControllerHarness {
  const _ControllerHarness(this.social, this.friends, this.gateway);

  final DiscordSocialSdkController social;
  final DiscordFriendsController friends;
  final _SocialGateway gateway;

  void dispose() {
    social.dispose();
    friends.dispose();
  }
}

DiscordRelationship _relationship({
  required String id,
  required String name,
  DiscordRelationshipKind kind = DiscordRelationshipKind.friend,
  DiscordPresenceStatus status = DiscordPresenceStatus.offline,
}) => DiscordRelationship(
  user: DiscordRelationshipUser(id: id, displayName: name, status: status),
  kind: kind,
);
