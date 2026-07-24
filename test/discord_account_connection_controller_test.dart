import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_account_connection_controller.dart';
import 'package:flucord/src/application/discord_oauth_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test(
    'connects OAuth and the native social grant through one action',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      expect(await harness.account.connect(), isTrue);

      expect(harness.oauthGateway.authorizeCalls, 1);
      expect(harness.socialGateway.authorizeCalls, 1);
      expect(harness.account.oauthLinked, isTrue);
      expect(harness.account.socialConnected, isTrue);
      expect(harness.account.state, DiscordAccountConnectionState.connected);
    },
  );

  test(
    'does not start native social authorization after OAuth fails',
    () async {
      final harness = await _Harness.create(oauthFailure: true);
      addTearDown(harness.dispose);

      expect(await harness.account.connect(), isFalse);

      expect(harness.oauthGateway.authorizeCalls, 1);
      expect(harness.socialGateway.authorizeCalls, 0);
      expect(harness.account.state, DiscordAccountConnectionState.failure);
      expect(harness.account.errorMessage, 'OAuth cancelled.');
    },
  );

  test(
    'treats an unbundled Social SDK as an honest OAuth-only connection',
    () async {
      final harness = await _Harness.create(
        availability: DiscordSocialSdkAvailability.sdkNotBundled,
      );
      addTearDown(harness.dispose);

      expect(await harness.account.connect(), isTrue);

      expect(harness.oauthGateway.authorizeCalls, 1);
      expect(harness.socialGateway.authorizeCalls, 0);
      expect(harness.account.oauthLinked, isTrue);
      expect(harness.account.socialConnected, isFalse);
      expect(harness.account.isFullyConnected, isTrue);
    },
  );

  test(
    'retries only the missing social authorization after partial failure',
    () async {
      final harness = await _Harness.create(socialFailure: true);
      addTearDown(harness.dispose);

      expect(await harness.account.connect(), isFalse);
      expect(harness.account.oauthLinked, isTrue);
      expect(harness.account.needsSocial, isTrue);
      expect(harness.oauthGateway.authorizeCalls, 1);
      expect(harness.socialGateway.authorizeCalls, 1);

      harness.socialGateway.failAuthorization = false;
      expect(await harness.account.connect(), isTrue);

      expect(harness.oauthGateway.authorizeCalls, 1);
      expect(harness.socialGateway.authorizeCalls, 2);
      expect(harness.account.state, DiscordAccountConnectionState.connected);
    },
  );

  test('disconnects both independent grants through one action', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    await harness.account.connect();

    expect(await harness.account.disconnect(), isTrue);

    expect(harness.oauthGateway.clearCalls, 1);
    expect(harness.socialGateway.disconnectCalls, 1);
    expect(harness.account.isConnected, isFalse);
    expect(harness.account.state, DiscordAccountConnectionState.disconnected);
  });
}

final class _Harness {
  _Harness(
    this.oauthGateway,
    this.socialGateway,
    this.oauth,
    this.social,
    this.account,
  );

  static Future<_Harness> create({
    DiscordSocialSdkAvailability availability =
        DiscordSocialSdkAvailability.ready,
    bool oauthFailure = false,
    bool socialFailure = false,
  }) async {
    final oauthGateway = _OAuthGateway(failAuthorization: oauthFailure);
    final socialGateway = _SocialGateway(
      availability: availability,
      failAuthorization: socialFailure,
    );
    final oauth = DiscordOAuthController(oauthGateway);
    final social = DiscordSocialSdkController(socialGateway);
    final account = DiscordAccountConnectionController(oauth, social);
    await Future.wait([oauth.initialize(), social.initialize()]);
    return _Harness(oauthGateway, socialGateway, oauth, social, account);
  }

  final _OAuthGateway oauthGateway;
  final _SocialGateway socialGateway;
  final DiscordOAuthController oauth;
  final DiscordSocialSdkController social;
  final DiscordAccountConnectionController account;

  void dispose() {
    account.dispose();
    oauth.dispose();
    social.dispose();
  }
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  _OAuthGateway({required this.failAuthorization});

  final bool failAuthorization;
  int authorizeCalls = 0;
  int clearCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() async {
    authorizeCalls++;
    if (failAuthorization) {
      throw const DiscordOAuthException('OAuth cancelled.');
    }
    return DiscordOAuthAccount(
      id: 'user-1',
      username: 'jack',
      displayName: 'Jack',
    );
  }

  @override
  Future<void> clear() async => clearCalls++;

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) => throw StateError('Membership is not part of this test.');

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => null;

  @override
  void dispose() {}
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  _SocialGateway({required this.availability, required this.failAuthorization});

  final DiscordSocialSdkAvailability availability;
  bool failAuthorization;
  int authorizeCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async {
    authorizeCalls++;
    if (failAuthorization) {
      throw const DiscordSocialSdkException('authorization_failed');
    }
    return DiscordSocialSdkAuthentication.ready;
  }

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      availability;

  @override
  Future<void> disconnect() async => disconnectCalls++;

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
