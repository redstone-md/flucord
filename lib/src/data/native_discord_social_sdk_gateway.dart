import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_sdk.dart';
import 'discord_social_relationship_mapper.dart';
import 'secure_discord_social_sdk_vault.dart';

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

final class NativeDiscordSocialSdkGateway
    implements DiscordSocialSdkGateway, DiscordSocialSdkAuthenticationEvents {
  NativeDiscordSocialSdkGateway({
    DiscordSocialSdkPlatformChannel? channel,
    this._targetPlatform,
    DiscordSocialSdkConfiguration? configuration,
    this._vault = const SecureDiscordSocialSdkGrantVault(),
    this._clock = DateTime.now,
  }) : _channel = channel ?? FlutterDiscordSocialSdkPlatformChannel(),
       _configuration =
           configuration ?? DiscordSocialSdkConfiguration.fromEnvironment() {
    _channel.setNativeHandler(_handleNativeCall);
  }

  final DiscordSocialSdkPlatformChannel _channel;
  final TargetPlatform? _targetPlatform;
  final DiscordSocialSdkConfiguration? _configuration;
  final DiscordSocialSdkGrantVault _vault;
  final DiscordSocialSdkClock _clock;
  final StreamController<DiscordSocialSdkAuthentication> _authChanges =
      StreamController.broadcast(sync: true);

  @override
  Stream<DiscordSocialSdkAuthentication> get authenticationChanges =>
      _authChanges.stream;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async {
    if (!_isSupportedPlatform) {
      return DiscordSocialSdkAvailability.unsupportedPlatform;
    }
    try {
      final response = await _channel.invoke('getAvailability');
      return _decodeAvailability(response);
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
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async {
    final configuration = _configuration;
    if (configuration == null) {
      return DiscordSocialSdkAuthentication.unconfigured;
    }
    _requireSupportedPlatform();
    final grant = await _vault.read();
    if (grant == null) return DiscordSocialSdkAuthentication.signedOut;
    try {
      final response = await _invoke(
        'restoreSession',
        arguments: {
          'client_id': configuration.clientId,
          'refresh_token': grant.refreshToken,
        },
      );
      await _persistGrant(response);
      return DiscordSocialSdkAuthentication.ready;
    } on DiscordSocialSdkException catch (error) {
      if (!_invalidGrantCodes.contains(error.code)) rethrow;
      await _vault.clear();
      return DiscordSocialSdkAuthentication.signedOut;
    }
  }

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async {
    final configuration = _configuration;
    if (configuration == null) {
      return DiscordSocialSdkAuthentication.unconfigured;
    }
    _requireSupportedPlatform();
    final response = await _invoke(
      'authorize',
      arguments: {'client_id': configuration.clientId},
    );
    await _persistGrant(response);
    return DiscordSocialSdkAuthentication.ready;
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_isSupportedPlatform) await _invoke('disconnect');
    } finally {
      await _vault.clear();
    }
  }

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    _requireSupportedPlatform();
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

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {
    _requireSupportedPlatform();
    await _invoke(
      'updateRelationship',
      arguments: {'user_id': userId, 'action': _actionName(action)},
    );
  }

  Future<Object?> _handleNativeCall(String method, Object? arguments) async {
    if (method == 'authenticationGrantChanged') {
      await _persistGrant(arguments);
      _authChanges.add(DiscordSocialSdkAuthentication.ready);
      return null;
    }
    if (method == 'authenticationExpired') {
      await _vault.clear();
      _authChanges.add(DiscordSocialSdkAuthentication.signedOut);
      return null;
    }
    throw MissingPluginException('Unknown Social SDK event: $method');
  }

  Future<void> _persistGrant(Object? response) async {
    final grant = _decodeGrant(response);
    await _vault.write(grant);
  }

  Future<Object?> _invoke(String method, {Object? arguments}) async {
    try {
      return await _channel.invoke(method, arguments);
    } on MissingPluginException {
      throw const DiscordSocialSdkException('unsupported_platform');
    } on PlatformException catch (error) {
      throw DiscordSocialSdkException(_safeCode(error.code));
    } on DiscordSocialSdkException {
      rethrow;
    } on Object {
      throw const DiscordSocialSdkException('channel_failure');
    }
  }

  void _requireSupportedPlatform() {
    if (!_isSupportedPlatform) {
      throw const DiscordSocialSdkException('unsupported_platform');
    }
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (_targetPlatform ?? defaultTargetPlatform) == TargetPlatform.windows;

  static DiscordSocialSdkAvailability _decodeAvailability(Object? response) {
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

  DiscordSocialSdkGrant _decodeGrant(Object? response) {
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
        expiresAt: _clock().toUtc().add(Duration(seconds: expiresIn)),
        scopes: scopes,
      );
    } on ArgumentError {
      throw const DiscordSocialSdkException('invalid_auth_response');
    }
  }

  static String _safeCode(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }

  static String _actionName(DiscordRelationshipAction action) =>
      switch (action) {
        DiscordRelationshipAction.acceptRequest => 'accept_request',
        DiscordRelationshipAction.rejectRequest => 'reject_request',
        DiscordRelationshipAction.cancelRequest => 'cancel_request',
        DiscordRelationshipAction.removeFriend => 'remove_friend',
        DiscordRelationshipAction.blockUser => 'block_user',
      };

  static const _invalidGrantCodes = {
    'not_authenticated',
    'refresh_failed',
    'authorization_expired',
  };
}
