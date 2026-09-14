import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('maps the authenticated Social SDK user snowflake', () async {
    final channel = _IdentityChannel({'user_id': '123456789012345678'});
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    expect(await gateway.fetchCurrentUserId(), '123456789012345678');
    expect(channel.calls, ['getCurrentUser']);
  });

  for (final payload in <Object?>[
    null,
    const <String, Object>{},
    const {'user_id': ''},
    const {'user_id': 'not-a-snowflake'},
    const {'user_id': '0'},
  ]) {
    test('rejects invalid current-user payload $payload', () async {
      final gateway = NativeDiscordSocialSdkGateway(
        channel: _IdentityChannel(payload),
        targetPlatform: TargetPlatform.windows,
      );

      await expectLater(
        gateway.fetchCurrentUserId(),
        throwsA(
          isA<DiscordSocialSdkException>().having(
            (error) => error.code,
            'code',
            'invalid_identity_response',
          ),
        ),
      );
    });
  }

  test('discards a grant when authorization cannot verify its user', () async {
    final channel = _AuthorizationChannel();
    final vault = _MemoryGrantVault();
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
      configuration: DiscordSocialSdkConfiguration(
        clientId: '123456789012345678',
      ),
      vault: vault,
    );

    await expectLater(
      gateway.authorize(),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'invalid_identity_response',
        ),
      ),
    );

    expect(vault.grant, isNull);
    expect(channel.calls, ['authorize', 'getCurrentUser', 'disconnect']);
  });
}

final class _IdentityChannel implements DiscordSocialSdkPlatformChannel {
  _IdentityChannel(this.response);

  final Object? response;
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return response;
  }

  @override
  void setNativeHandler(DiscordSocialSdkNativeHandler? handler) {}
}

final class _AuthorizationChannel implements DiscordSocialSdkPlatformChannel {
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return switch (method) {
      'authorize' => {
        'access_token': 'access-secret',
        'refresh_token': 'refresh-secret',
        'expires_in': 3600,
        'scopes': 'identify',
      },
      'getCurrentUser' => const {'user_id': 'invalid'},
      _ => null,
    };
  }

  @override
  void setNativeHandler(DiscordSocialSdkNativeHandler? handler) {}
}

final class _MemoryGrantVault implements DiscordSocialSdkGrantVault {
  DiscordSocialSdkGrant? grant;

  @override
  Future<void> clear() async => grant = null;

  @override
  Future<DiscordSocialSdkGrant?> read() async => grant;

  @override
  Future<void> write(DiscordSocialSdkGrant grant) async {
    this.grant = grant;
  }
}
