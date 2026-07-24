import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('maps a linked native SDK response', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel({'status': 'ready'}),
      TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(availability.status, DiscordSocialSdkAvailabilityStatus.ready);
    expect(availability.isReady, isTrue);
  });

  test('maps a Windows build without the SDK package', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel({'status': 'sdk_not_bundled'}),
      TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    );
  });

  test('maps a missing native bridge to an unsupported platform', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel.error(MissingPluginException()),
      TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.unsupportedPlatform,
    );
  });

  test('keeps platform failures typed and redacted', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel.error(PlatformException(code: 'SDK Load Failed!')),
      TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(availability.status, DiscordSocialSdkAvailabilityStatus.failure);
    expect(availability.diagnosticCode, 'platform_sdk_load_failed');
  });

  test('does not call the Windows bridge on another platform', () async {
    final channel = _Channel({'status': 'ready'});
    final gateway = NativeDiscordSocialSdkGateway(
      channel,
      TargetPlatform.linux,
    );

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.unsupportedPlatform,
    );
    expect(channel.calls, isEmpty);
  });

  test('maps native relationship payloads through the same channel', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel([
        {
          'id': 'user-1',
          'display_name': 'Ada',
          'status': 'online',
          'relationship_type': 'friend',
        },
      ]),
      TargetPlatform.windows,
    );

    final relationships = await gateway.fetchRelationships();

    expect(relationships.single.user.displayName, 'Ada');
    expect(relationships.single.user.status.name, 'online');
  });

  test('preserves native relationship error codes', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      _Channel.error(PlatformException(code: 'not_authenticated')),
      TargetPlatform.windows,
    );

    await expectLater(
      gateway.fetchRelationships(),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'not_authenticated',
        ),
      ),
    );
  });
}

final class _Channel implements DiscordSocialSdkPlatformChannel {
  _Channel(this._response) : _error = null;

  _Channel.error(Object error) : _response = null, _error = error;

  final Object? _response;
  final Object? _error;
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String method) async {
    calls.add(method);
    if (_error case final error?) throw error;
    return _response;
  }
}
