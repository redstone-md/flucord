import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('initializes once while a capability check is in flight', () async {
    final completer = Completer<DiscordSocialSdkAvailability>();
    final gateway = _SocialGateway(() => completer.future);
    final controller = DiscordSocialSdkController(gateway);
    addTearDown(controller.dispose);

    final first = controller.initialize();
    final second = controller.initialize();

    expect(controller.state, DiscordSocialSdkControllerState.checking);
    expect(gateway.calls, 1);
    completer.complete(DiscordSocialSdkAvailability.ready);
    await Future.wait([first, second]);

    expect(controller.state, DiscordSocialSdkControllerState.ready);
    expect(controller.availability?.isReady, isTrue);
  });

  test('keeps an absent package distinct from a failed check', () async {
    final gateway = _SocialGateway(
      () async => DiscordSocialSdkAvailability.sdkNotBundled,
    );
    final controller = DiscordSocialSdkController(gateway);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state, DiscordSocialSdkControllerState.unavailable);
    expect(
      controller.availability?.status,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    );
  });

  test('retry replaces a failure with the latest availability', () async {
    var shouldFail = true;
    final gateway = _SocialGateway(
      () async => shouldFail
          ? DiscordSocialSdkAvailability.failure('load_failure')
          : DiscordSocialSdkAvailability.ready,
    );
    final controller = DiscordSocialSdkController(gateway);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.state, DiscordSocialSdkControllerState.failure);

    shouldFail = false;
    await controller.retry();

    expect(controller.state, DiscordSocialSdkControllerState.ready);
    expect(gateway.calls, 2);
  });

  test(
    'keeps a bundled SDK signed out until native authorization succeeds',
    () async {
      final gateway = _SocialGateway(
        () async => DiscordSocialSdkAvailability.ready,
        restored: DiscordSocialSdkAuthentication.signedOut,
      );
      final controller = DiscordSocialSdkController(gateway);
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.state, DiscordSocialSdkControllerState.signedOut);

      await controller.authorize();
      expect(controller.state, DiscordSocialSdkControllerState.ready);
      expect(gateway.authorizationCalls, 1);
    },
  );

  test(
    'surfaces a missing application id separately from SDK absence',
    () async {
      final gateway = _SocialGateway(
        () async => DiscordSocialSdkAvailability.ready,
        restored: DiscordSocialSdkAuthentication.unconfigured,
      );
      final controller = DiscordSocialSdkController(gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state, DiscordSocialSdkControllerState.unconfigured);
      expect(controller.availability?.isReady, isTrue);
    },
  );

  test('disconnects an authenticated native session', () async {
    final gateway = _SocialGateway(
      () async => DiscordSocialSdkAvailability.ready,
    );
    final controller = DiscordSocialSdkController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.disconnect();

    expect(controller.state, DiscordSocialSdkControllerState.signedOut);
    expect(gateway.disconnectCalls, 1);
  });

  test('leaves ready state when the native refresh grant expires', () async {
    final gateway = _SocialGateway(
      () async => DiscordSocialSdkAvailability.ready,
    );
    final controller = DiscordSocialSdkController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();

    gateway.emitAuthentication(DiscordSocialSdkAuthentication.signedOut);

    expect(controller.state, DiscordSocialSdkControllerState.signedOut);
    expect(controller.isAuthenticated, isFalse);
  });
}

final class _SocialGateway
    implements DiscordSocialSdkGateway, DiscordSocialSdkAuthenticationEvents {
  _SocialGateway(
    this._check, {
    this.restored = DiscordSocialSdkAuthentication.ready,
  });

  final Future<DiscordSocialSdkAvailability> Function() _check;
  final DiscordSocialSdkAuthentication restored;
  int calls = 0;
  int authorizationCalls = 0;
  int disconnectCalls = 0;
  final StreamController<DiscordSocialSdkAuthentication> _authChanges =
      StreamController.broadcast(sync: true);

  @override
  Stream<DiscordSocialSdkAuthentication> get authenticationChanges =>
      _authChanges.stream;

  void emitAuthentication(DiscordSocialSdkAuthentication authentication) {
    _authChanges.add(authentication);
  }

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async {
    authorizationCalls++;
    return DiscordSocialSdkAuthentication.ready;
  }

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() {
    calls++;
    return _check();
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => const [];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      restored;

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}
