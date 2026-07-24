import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/oauth_guild_membership_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  test(
    'loads and caches membership independently from guild selection',
    () async {
      final gateway = _OAuthGateway();
      final controller = OAuthGuildMembershipController(gateway)
        ..reconcileAccount('user-1');
      addTearDown(controller.dispose);
      final response = Completer<DiscordOAuthGuildMembership>();
      gateway.responses.add(response.future);

      final loading = controller.load('guild-1');
      expect(
        controller.snapshotFor('guild-1').state,
        OAuthGuildMembershipLoadState.loading,
      );
      response.complete(
        DiscordOAuthGuildMembership(guildId: 'guild-1', nickname: 'Fly'),
      );
      await loading;

      final ready = controller.snapshotFor('guild-1');
      expect(ready.state, OAuthGuildMembershipLoadState.ready);
      expect(ready.membership?.nickname, 'Fly');
      await controller.load('guild-1');
      expect(gateway.guildIds, const ['guild-1']);
    },
  );

  test(
    'retries failures and drops stale responses after account changes',
    () async {
      final gateway = _OAuthGateway();
      final controller = OAuthGuildMembershipController(gateway)
        ..reconcileAccount('user-1');
      addTearDown(controller.dispose);
      gateway.responses.add(
        Future.error(const DiscordOAuthException('Membership denied.')),
      );

      await controller.load('guild-1');
      expect(
        controller.snapshotFor('guild-1').errorMessage,
        'Membership denied.',
      );

      final stale = Completer<DiscordOAuthGuildMembership>();
      gateway.responses.add(stale.future);
      final retry = controller.retry('guild-1');
      controller.reconcileAccount('user-2');
      stale.complete(DiscordOAuthGuildMembership(guildId: 'guild-1'));
      await retry;

      expect(
        controller.snapshotFor('guild-1').state,
        OAuthGuildMembershipLoadState.idle,
      );
      expect(gateway.guildIds, const ['guild-1', 'guild-1']);
    },
  );
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  final List<Future<DiscordOAuthGuildMembership>> responses = [];
  final List<String> guildIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() =>
      throw StateError('Authorization is not part of this test.');

  @override
  Future<void> clear() async {}

  @override
  void dispose() {}

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) {
    guildIds.add(guildId);
    return responses.removeAt(0);
  }

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => null;
}
