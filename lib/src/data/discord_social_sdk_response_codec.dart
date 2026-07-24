import '../domain/discord_relationship.dart';
import '../domain/discord_social_sdk.dart';
import 'discord_social_sdk_platform_channel.dart';

abstract final class DiscordSocialSdkResponseCodec {
  static DiscordSocialSdkAvailability availability(Object? response) {
    if (response is! Map<Object?, Object?>) {
      return DiscordSocialSdkAvailability.failure('invalid_response');
    }
    return switch (response['status']) {
      'ready' => DiscordSocialSdkAvailability.ready,
      'sdk_not_bundled' => DiscordSocialSdkAvailability.sdkNotBundled,
      'unsupported_platform' =>
        DiscordSocialSdkAvailability.unsupportedPlatform,
      final String value => DiscordSocialSdkAvailability.failure(
        'unknown_status_${safeCode(value)}',
      ),
      _ => DiscordSocialSdkAvailability.failure('missing_status'),
    };
  }

  static DiscordSocialSdkGrant grant(
    Object? response,
    DiscordSocialSdkClock clock,
  ) {
    if (response is! Map<Object?, Object?>) {
      throw const DiscordSocialSdkException('invalid_auth_response');
    }
    final accessToken = response['access_token'];
    final refreshToken = response['refresh_token'];
    final expiresIn = response['expires_in'];
    final scopes = switch (response['scopes']) {
      final String value => value.split(RegExp(r'\s+')),
      final List<Object?> values => values.whereType<String>(),
      _ => const <String>[],
    };
    if (accessToken is! String ||
        refreshToken is! String ||
        expiresIn is! int ||
        expiresIn <= 0) {
      throw const DiscordSocialSdkException('invalid_auth_response');
    }
    try {
      return DiscordSocialSdkGrant(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: clock().toUtc().add(Duration(seconds: expiresIn)),
        scopes: scopes,
      );
    } on ArgumentError {
      throw const DiscordSocialSdkException('invalid_auth_response');
    }
  }

  static String requiredIdentifier(Object? payload, String key) {
    if (payload is! Map<Object?, Object?>) {
      throw ArgumentError.value(payload, 'payload', 'Must be a map.');
    }
    final value = switch (payload[key]) {
      final String value => value.trim(),
      final int value => value.toString(),
      _ => '',
    };
    if (value.isEmpty) {
      throw ArgumentError.value(payload[key], key, 'Must not be empty.');
    }
    return value;
  }

  static String safeCode(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}
