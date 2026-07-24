import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/discord_social_sdk.dart';

abstract interface class DiscordSocialSdkPlatformChannel {
  Future<Object?> invoke(String method);
}

final class FlutterDiscordSocialSdkPlatformChannel
    implements DiscordSocialSdkPlatformChannel {
  const FlutterDiscordSocialSdkPlatformChannel([
    this._channel = const MethodChannel('flucord/social_sdk'),
  ]);

  final MethodChannel _channel;

  @override
  Future<Object?> invoke(String method) =>
      _channel.invokeMethod<Object?>(method);
}

final class NativeDiscordSocialSdkGateway implements DiscordSocialSdkGateway {
  const NativeDiscordSocialSdkGateway([
    this._channel = const FlutterDiscordSocialSdkPlatformChannel(),
    this._targetPlatform,
  ]);

  final DiscordSocialSdkPlatformChannel _channel;
  final TargetPlatform? _targetPlatform;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async {
    if (kIsWeb ||
        (_targetPlatform ?? defaultTargetPlatform) != TargetPlatform.windows) {
      return DiscordSocialSdkAvailability.unsupportedPlatform;
    }
    try {
      final response = await _channel.invoke('getAvailability');
      return _decode(response);
    } on MissingPluginException {
      return DiscordSocialSdkAvailability.unsupportedPlatform;
    } on PlatformException catch (error) {
      return DiscordSocialSdkAvailability.failure(
        'platform_${_safeCode(error.code)}',
      );
    } on Object {
      return DiscordSocialSdkAvailability.failure('channel_failure');
    }
  }

  static DiscordSocialSdkAvailability _decode(Object? response) {
    if (response is! Map<Object?, Object?>) {
      return DiscordSocialSdkAvailability.failure('invalid_response');
    }
    return switch (response['status']) {
      'ready' => DiscordSocialSdkAvailability.ready,
      'sdk_not_bundled' => DiscordSocialSdkAvailability.sdkNotBundled,
      'unsupported_platform' =>
        DiscordSocialSdkAvailability.unsupportedPlatform,
      final String value => DiscordSocialSdkAvailability.failure(
        'unknown_status_${_safeCode(value)}',
      ),
      _ => DiscordSocialSdkAvailability.failure('missing_status'),
    };
  }

  static String _safeCode(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}
