import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/account_connection_coordination.dart';
import 'package:flucord/src/application/discord_account_connection_controller.dart';
import 'package:flucord/src/application/discord_friends_controller.dart';
import 'package:flucord/src/application/discord_oauth_controller.dart';
import 'package:flucord/src/application/discord_social_activity_controller.dart';
import 'package:flucord/src/application/discord_social_dm_controller.dart';
import 'package:flucord/src/application/discord_social_presence_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/application/oauth_guild_directory_controller.dart';
import 'package:flucord/src/application/oauth_guild_membership_controller.dart';
import 'package:flucord/src/data/unavailable_discord_social_dm_gateway.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('the guild surfaces follow the OAuth account', () async {
    final gateway = _OAuthGateway(restoredAccount: _account());
    final oauth = DiscordOAuthController(gateway);
    final directory = OAuthGuildDirectoryController();
    final membership = OAuthGuildMembershipController(gateway);
    final coordination = _buildCoordination(
      oauth: oauth,
      directory: directory,
      membership: membership,
    );

    await oauth.initialize();

    expect(
      directory.selectedGuildId,
      'guild-1',
      reason: 'the directory landed on the account’s first guild',
    );

    coordination.dispose();
  });

  test('friends follow the Social SDK session once it is allowed', () async {
    final oauth = DiscordOAuthController(
      _OAuthGateway(restoredAccount: _account()),
    );
    final socialGateway = _ReadySocialGateway();
    final socialSdk = DiscordSocialSdkController(socialGateway);
    final friends = DiscordFriendsController(socialGateway);
    final coordination = _buildCoordination(
      oauth: oauth,
      socialSdk: socialSdk,
      friends: friends,
    );

    await oauth.initialize();
    await socialSdk.initialize();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(friends.state, DiscordFriendsLoadState.ready);
    expect(
      friends.relationships.map((relationship) => relationship.user.id),
      contains('friend-1'),
    );

    coordination.dispose();
  });
}

AccountConnectionCoordination _buildCoordination({
  required DiscordOAuthController oauth,
  OAuthGuildDirectoryController? directory,
  OAuthGuildMembershipController? membership,
  DiscordSocialSdkController? socialSdk,
  DiscordFriendsController? friends,
}) {
  final resolvedSocial = socialSdk ?? DiscordSocialSdkController(_AbsentSdk());
  return AccountConnectionCoordination(
    oauth: oauth,
    accountConnection: DiscordAccountConnectionController(
      oauth,
      resolvedSocial,
    ),
    socialSdk: resolvedSocial,
    directory: directory ?? OAuthGuildDirectoryController(),
    membership: membership ?? OAuthGuildMembershipController(_OAuthGateway()),
    friends:
        friends ??
        DiscordFriendsController(
          _ReadySocialGateway(
            restoredAuthentication: DiscordSocialSdkAuthentication.signedOut,
          ),
        ),
    socialDm: DiscordSocialDmController(
      const UnavailableDiscordSocialDmGateway(),
    ),
    socialPresence: DiscordSocialPresenceController(null),
    socialActivity: DiscordSocialActivityController(null),
  );
}

class _OAuthGateway implements DiscordOAuthAccountGateway {
  _OAuthGateway({this.restoredAccount});

  final DiscordOAuthAccount? restoredAccount;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() => throw StateError('unused');

  @override
  Future<void> clear() async {}

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) async => DiscordOAuthGuildMembership(
    guildId: guildId,
    nickname: 'Jack',
    joinedAt: DateTime.utc(2024, 1, 2),
  );

  @override
  void dispose() {}

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => restoredAccount;
}

class _ReadySocialGateway implements DiscordSocialSdkGateway {
  _ReadySocialGateway({
    DiscordSocialSdkAuthentication? restoredAuthentication,
  }) : restoredAuthentication =
          restoredAuthentication ??
          DiscordSocialSdkAuthentication.readyFor('user-1');

  final DiscordSocialSdkAuthentication restoredAuthentication;

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async =>
      DiscordSocialSdkAuthentication.readyFor('user-1');

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => [
    DiscordRelationship(
      user: DiscordRelationshipUser(
        id: 'friend-1',
        displayName: 'Ada',
        status: DiscordPresenceStatus.online,
      ),
      kind: DiscordRelationshipKind.friend,
    ),
  ];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      restoredAuthentication;

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}

class _AbsentSdk implements DiscordSocialSdkGateway {
  @override
  Future<DiscordSocialSdkAuthentication> authorize() async =>
      DiscordSocialSdkAuthentication.signedOut;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.sdkNotBundled;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => const [];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      DiscordSocialSdkAuthentication.signedOut;

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}

DiscordOAuthAccount _account() => DiscordOAuthAccount(
  id: 'user-1',
  username: 'jack',
  displayName: 'Jack',
  guilds: [
    DiscordOAuthGuild(id: 'guild-1', name: 'The Forge', isOwner: true),
    DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift', permissions: '8'),
  ],
);
