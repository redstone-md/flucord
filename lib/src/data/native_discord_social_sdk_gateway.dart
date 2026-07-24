import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_sdk.dart';
import 'discord_social_relationship_mapper.dart';

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
    if (!_isSupportedPlatform) {
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

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    if (!_isSupportedPlatform) {
      throw const DiscordSocialSdkException('unsupported_platform');
    }
    try {
      final response = await _channel.invoke('getRelationships');
      return DiscordSocialRelationshipMapper.decode(response);
    } on MissingPluginException {
      throw const DiscordSocialSdkException('unsupported_platform');
    } on PlatformException catch (error) {
      throw DiscordSocialSdkException(_safeCode(error.code));
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_response');
    } on DiscordSocialSdkException {
      rethrow;
    } on Object {
      throw const DiscordSocialSdkException('channel_failure');
    }
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (_targetPlatform ?? defaultTargetPlatform) == TargetPlatform.windows;

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
