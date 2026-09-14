import 'package:flutter/services.dart';

typedef DiscordSocialSdkNativeHandler =
    Future<Object?> Function(String method, Object? arguments);
typedef DiscordSocialSdkClock = DateTime Function();

abstract interface class DiscordSocialSdkPlatformChannel {
  Future<Object?> invoke(String method, [Object? arguments]);

  void setNativeHandler(DiscordSocialSdkNativeHandler? handler);
}

final class FlutterDiscordSocialSdkPlatformChannel
    implements DiscordSocialSdkPlatformChannel {
  FlutterDiscordSocialSdkPlatformChannel([
    this._channel = const MethodChannel('flucord/social_sdk'),
  ]);

  final MethodChannel _channel;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) =>
      _channel.invokeMethod<Object?>(method, arguments);

  @override
  void setNativeHandler(DiscordSocialSdkNativeHandler? handler) {
    _channel.setMethodCallHandler(
      handler == null ? null : (call) => handler(call.method, call.arguments),
    );
  }
}

final class DiscordSocialSdkConfiguration {
  factory DiscordSocialSdkConfiguration({required String clientId}) {
    final normalized = clientId.trim();
    final value = BigInt.tryParse(normalized);
    if (value == null || value <= BigInt.zero || value.bitLength > 64) {
      throw ArgumentError.value(clientId, 'clientId', 'Must be a uint64.');
    }
    return DiscordSocialSdkConfiguration._(normalized);
  }

  const DiscordSocialSdkConfiguration._(this.clientId);

  static DiscordSocialSdkConfiguration? fromEnvironment() {
    const clientId = String.fromEnvironment('FLUCORD_DISCORD_CLIENT_ID');
    if (clientId.trim().isEmpty) return null;
    return DiscordSocialSdkConfiguration(clientId: clientId);
  }

  final String clientId;
}
