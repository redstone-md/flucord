import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_presence_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_presence.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('sends the initial online selection to the native SDK', () async {
    final gateway = _PresenceGateway();
    final controller = DiscordSocialPresenceController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    expect(await controller.setStatus(DiscordOnlineStatus.online), isTrue);
    expect(gateway.statuses, [DiscordOnlineStatus.online]);
  });

  test('confirms a status only after the native mutation completes', () async {
    final completer = Completer<void>();
    final gateway = _PresenceGateway()..completer = completer;
    final controller = DiscordSocialPresenceController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    final operation = controller.setStatus(DiscordOnlineStatus.idle);

    expect(controller.state, DiscordSocialPresenceState.updating);
    expect(controller.pendingStatus, DiscordOnlineStatus.idle);
    expect(controller.status, DiscordOnlineStatus.online);

    completer.complete();
    expect(await operation, isTrue);
    expect(controller.state, DiscordSocialPresenceState.ready);
    expect(controller.status, DiscordOnlineStatus.idle);
    expect(controller.pendingStatus, isNull);
  });

  test('retains the confirmed status when Discord rejects an update', () async {
    final gateway = _PresenceGateway()..errorCode = 'rate_limited';
    final controller = DiscordSocialPresenceController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    expect(
      await controller.setStatus(DiscordOnlineStatus.doNotDisturb),
      isFalse,
    );
    expect(controller.status, DiscordOnlineStatus.online);
    expect(controller.state, DiscordSocialPresenceState.failure);
    expect(controller.errorCode, 'rate_limited');
  });

  test('disables status mutation when the native session is revoked', () async {
    final gateway = _PresenceGateway();
    final controller = DiscordSocialPresenceController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: false,
    );

    expect(controller.state, DiscordSocialPresenceState.unavailable);
    expect(await controller.setStatus(DiscordOnlineStatus.invisible), isFalse);
    expect(gateway.statuses, isEmpty);
  });
}

final class _PresenceGateway implements DiscordSocialPresenceGateway {
  final List<DiscordOnlineStatus> statuses = [];
  Completer<void>? completer;
  String? errorCode;

  @override
  Future<void> setOnlineStatus(DiscordOnlineStatus status) async {
    statuses.add(status);
    if (completer case final pending?) await pending.future;
    if (errorCode case final code?) throw DiscordSocialSdkException(code);
  }
}
