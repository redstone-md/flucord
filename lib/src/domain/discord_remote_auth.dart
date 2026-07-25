import 'discord_session.dart';

sealed class DiscordRemoteAuthEvent {
  const DiscordRemoteAuthEvent();
}

final class DiscordRemoteAuthQrReady extends DiscordRemoteAuthEvent {
  const DiscordRemoteAuthQrReady(this.fingerprint);

  final String fingerprint;
  Uri get qrUri => Uri.https('discord.com', '/ra/$fingerprint');
}

final class DiscordRemoteAuthUserPending extends DiscordRemoteAuthEvent {
  const DiscordRemoteAuthUserPending({
    required this.username,
    this.discriminator,
    this.avatarHash,
  });

  final String username;
  final String? discriminator;
  final String? avatarHash;

  String get displayName => discriminator == null || discriminator == '0'
      ? username
      : '$username#$discriminator';
}

final class DiscordRemoteAuthCaptchaChallenge {
  const DiscordRemoteAuthCaptchaChallenge({
    required this.siteKey,
    required this.service,
    required this.userAgent,
    this.rqData,
    this.rqToken,
    this.sessionId,
    this.serveInvisible = false,
  });

  final String siteKey;
  final String service;
  final String userAgent;
  final String? rqData;
  final String? rqToken;
  final String? sessionId;
  final bool serveInvisible;

  @override
  String toString() =>
      'DiscordRemoteAuthCaptchaChallenge(service: $service, <data redacted>)';
}

final class DiscordRemoteAuthCaptchaRequired extends DiscordRemoteAuthEvent {
  const DiscordRemoteAuthCaptchaRequired(this.challenge);

  final DiscordRemoteAuthCaptchaChallenge challenge;
}

final class DiscordRemoteAuthCompleted extends DiscordRemoteAuthEvent {
  const DiscordRemoteAuthCompleted(this.session);

  final DiscordDesktopUserSession session;
}

final class DiscordRemoteAuthFailed extends DiscordRemoteAuthEvent {
  const DiscordRemoteAuthFailed(this.message);

  final String message;
}

abstract interface class DiscordRemoteAuthGateway {
  Stream<DiscordRemoteAuthEvent> get events;

  Future<void> start();

  Future<void> submitCaptcha(String response);

  Future<void> close();
}

abstract interface class DiscordRemoteAuthGatewayFactory {
  DiscordRemoteAuthGateway create();
}
