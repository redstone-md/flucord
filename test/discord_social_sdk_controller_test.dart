import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
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
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  _SocialGateway(this._check);

  final Future<DiscordSocialSdkAvailability> Function() _check;
  int calls = 0;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() {
    calls++;
    return _check();
  }
}
