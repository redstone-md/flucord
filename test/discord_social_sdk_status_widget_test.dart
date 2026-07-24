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
}

Future<_ControllerHarness> _harnessFor(
  DiscordSocialSdkAvailability availability, {
  List<DiscordRelationship> relationships = const [],
  String? relationshipError,
}) async {
  final gateway = _SocialGateway(
    availability,
    relationships,
    relationshipError,
  );
  final social = DiscordSocialSdkController(gateway);
  final friends = DiscordFriendsController(gateway);
  await social.initialize();
  friends.reconcileAvailability(social.availability);
  await friends.initialize();
  return _ControllerHarness(social, friends);
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
  const _SocialGateway(
    this.availability,
    this.relationships,
    this.relationshipError,
  );

  final DiscordSocialSdkAvailability availability;
  final List<DiscordRelationship> relationships;
  final String? relationshipError;

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
}

final class _ControllerHarness {
  const _ControllerHarness(this.social, this.friends);

  final DiscordSocialSdkController social;
  final DiscordFriendsController friends;

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
