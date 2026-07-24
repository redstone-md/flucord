import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_dm.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  const clientId = '123456789012345678';
  final configuration = DiscordSocialSdkConfiguration(clientId: clientId);

  test('maps a linked native SDK response', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      channel: _Channel({'status': 'ready'}),
      targetPlatform: TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(availability.status, DiscordSocialSdkAvailabilityStatus.ready);
    expect(availability.isReady, isTrue);
  });

  test('maps a Windows build without the SDK package', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      channel: _Channel({'status': 'sdk_not_bundled'}),
      targetPlatform: TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    );
  });

  test('maps a missing native bridge to an unsupported platform', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      channel: _Channel.error(MissingPluginException()),
      targetPlatform: TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.unsupportedPlatform,
    );
  });

  test('keeps platform failures typed and redacted', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      channel: _Channel.error(PlatformException(code: 'SDK Load Failed!')),
      targetPlatform: TargetPlatform.windows,
    );

    final availability = await gateway.checkAvailability();

    expect(availability.status, DiscordSocialSdkAvailabilityStatus.failure);
    expect(availability.diagnosticCode, 'platform_sdk_load_failed');
  });

  test('does not call the Windows bridge on another platform', () async {
    final channel = _Channel({'status': 'ready'});
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.linux,
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
      channel: _Channel([
        {
          'id': 'user-1',
          'display_name': 'Ada',
          'status': 'online',
          'relationship_type': 'friend',
        },
      ]),
      targetPlatform: TargetPlatform.windows,
    );

    final relationships = await gateway.fetchRelationships();

    expect(relationships.single.user.displayName, 'Ada');
    expect(relationships.single.user.status.name, 'online');
  });

  test('preserves native relationship error codes', () async {
    final gateway = NativeDiscordSocialSdkGateway(
      channel: _Channel.error(PlatformException(code: 'not_authenticated')),
      targetPlatform: TargetPlatform.windows,
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

  test(
    'maps typed relationship mutations to the native wire contract',
    () async {
      final channel = _Channel(null);
      final gateway = NativeDiscordSocialSdkGateway(
        channel: channel,
        targetPlatform: TargetPlatform.windows,
      );

      await gateway.updateRelationship(
        userId: '123456789012345678',
        action: DiscordRelationshipAction.blockUser,
      );

      expect(channel.calls, ['updateRelationship']);
      expect(channel.arguments.single, {
        'user_id': '123456789012345678',
        'action': 'block_user',
      });
    },
  );

  test('maps native DM summaries through the official chat method', () async {
    final channel = _Channel([
      {
        'user_id': '101',
        'last_message_id': '901',
        'display_name': 'Ada',
        'username': 'ada',
        'status': 'online',
        'is_provisional': false,
      },
    ]);
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    final conversations = await gateway.fetchConversations();

    expect(channel.calls, ['getDmConversations']);
    expect(conversations.single.user.displayName, 'Ada');
    expect(conversations.single.lastMessageId, '901');
  });

  test('bounds DM history and preserves the native wire identifiers', () async {
    final channel = _Channel([
      {
        'id': '901',
        'conversation_user_id': '101',
        'author_id': '101',
        'recipient_id': '202',
        'author_display_name': 'Ada',
        'content': 'hello',
        'sent_timestamp': 1771718400000,
        'edited_timestamp': 0,
        'authored_by_current_user': false,
      },
    ]);
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    final messages = await gateway.fetchMessages(userId: '101', limit: 400);

    expect(channel.calls, ['getDmMessages']);
    expect(channel.arguments.single, {'user_id': '101', 'limit': 100});
    expect(messages.single.content, 'hello');
  });

  test('sends DMs and decodes live message events', () async {
    final channel = _Channel({'message_id': '902'});
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    final messageId = await gateway.sendMessage(
      userId: '101',
      content: ' hello ',
    );
    final eventExpectation = expectLater(
      gateway.socialDmEvents,
      emits(
        isA<DiscordSocialDmEvent>()
            .having(
              (event) => event.type,
              'type',
              DiscordSocialDmEventType.created,
            )
            .having((event) => event.message?.content, 'content', 'live'),
      ),
    );
    await channel.emit('socialMessageChanged', {
      'type': 'created',
      'message': {
        'id': '902',
        'conversation_user_id': '101',
        'author_id': '202',
        'recipient_id': '101',
        'author_display_name': 'Jack',
        'content': 'live',
        'sent_timestamp': 1771718400000,
        'edited_timestamp': 0,
        'authored_by_current_user': true,
      },
    });
    await eventExpectation;

    expect(messageId, '902');
    expect(channel.calls, ['sendDmMessage']);
    expect(channel.arguments.single, {'user_id': '101', 'content': ' hello '});
  });

  test('maps edit, delete, and chat visibility to native methods', () async {
    final channel = _Channel(null);
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    await gateway.editMessage(
      userId: '101',
      messageId: '902',
      content: ' edited ',
    );
    await gateway.deleteMessage(userId: '101', messageId: '902');
    await gateway.setShowingChat(true);

    expect(channel.calls, [
      'editDmMessage',
      'deleteDmMessage',
      'setShowingChat',
    ]);
    expect(channel.arguments, [
      {'user_id': '101', 'message_id': '902', 'content': ' edited '},
      {'user_id': '101', 'message_id': '902'},
      {'showing': true},
    ]);
  });

  test(
    'authorizes through the native PKCE bridge and persists its grant',
    () async {
      final channel = _Channel(_grantPayload());
      final vault = _MemoryGrantVault();
      final gateway = NativeDiscordSocialSdkGateway(
        channel: channel,
        targetPlatform: TargetPlatform.windows,
        configuration: configuration,
        vault: vault,
        clock: () => DateTime.utc(2026, 2, 22),
      );

      final authentication = await gateway.authorize();

      expect(authentication.isReady, isTrue);
      expect(channel.calls, ['authorize']);
      expect(channel.arguments.single, {'client_id': clientId});
      expect(vault.grant?.refreshToken, 'refresh-secret');
      expect(vault.grant?.expiresAt, DateTime.utc(2026, 2, 22, 1));
    },
  );

  test(
    'returns signed out without touching native code when no grant exists',
    () async {
      final channel = _Channel(_grantPayload());
      final gateway = NativeDiscordSocialSdkGateway(
        channel: channel,
        targetPlatform: TargetPlatform.windows,
        configuration: configuration,
        vault: _MemoryGrantVault(),
      );

      final authentication = await gateway.restoreAuthentication();

      expect(
        authentication.status,
        DiscordSocialSdkAuthenticationStatus.signedOut,
      );
      expect(channel.calls, isEmpty);
    },
  );

  test('rotates a saved refresh grant through the native bridge', () async {
    final vault = _MemoryGrantVault()..grant = _grant('old-refresh');
    final channel = _Channel(_grantPayload());
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
      configuration: configuration,
      vault: vault,
    );

    final authentication = await gateway.restoreAuthentication();

    expect(authentication.isReady, isTrue);
    expect(channel.calls, ['restoreSession']);
    expect(channel.arguments.single, {
      'client_id': clientId,
      'refresh_token': 'old-refresh',
    });
    expect(vault.grant?.refreshToken, 'refresh-secret');
  });

  test(
    'clears an invalid saved grant after native refresh rejection',
    () async {
      final vault = _MemoryGrantVault()..grant = _grant('expired-refresh');
      final gateway = NativeDiscordSocialSdkGateway(
        channel: _Channel.error(PlatformException(code: 'refresh_failed')),
        targetPlatform: TargetPlatform.windows,
        configuration: configuration,
        vault: vault,
      );

      final authentication = await gateway.restoreAuthentication();

      expect(
        authentication.status,
        DiscordSocialSdkAuthenticationStatus.signedOut,
      );
      expect(vault.grant, isNull);
    },
  );

  test(
    'persists a background token rotation delivered by native code',
    () async {
      final channel = _Channel(null);
      final vault = _MemoryGrantVault();
      final gateway = NativeDiscordSocialSdkGateway(
        channel: channel,
        targetPlatform: TargetPlatform.windows,
        configuration: configuration,
        vault: vault,
      );
      final readyEvent = expectLater(
        gateway.authenticationChanges,
        emits(
          isA<DiscordSocialSdkAuthentication>().having(
            (value) => value.status,
            'status',
            DiscordSocialSdkAuthenticationStatus.ready,
          ),
        ),
      );

      await channel.emit('authenticationGrantChanged', _grantPayload());
      await readyEvent;

      expect(vault.grant?.accessToken, 'access-secret');
      expect(vault.grant?.toString(), 'DiscordSocialSdkGrant(<redacted>)');

      final expiredEvent = expectLater(
        gateway.authenticationChanges,
        emits(
          isA<DiscordSocialSdkAuthentication>().having(
            (value) => value.status,
            'status',
            DiscordSocialSdkAuthenticationStatus.signedOut,
          ),
        ),
      );
      await channel.emit('authenticationExpired');
      await expiredEvent;
      expect(vault.grant, isNull);
    },
  );
}

Map<String, Object> _grantPayload() => {
  'access_token': 'access-secret',
  'refresh_token': 'refresh-secret',
  'expires_in': 3600,
  'scopes': 'identify relationships.read',
};

DiscordSocialSdkGrant _grant(String refreshToken) => DiscordSocialSdkGrant(
  accessToken: 'old-access',
  refreshToken: refreshToken,
  expiresAt: DateTime.utc(2026, 2, 22),
  scopes: const ['identify'],
);

final class _Channel implements DiscordSocialSdkPlatformChannel {
  _Channel(this._response) : _error = null;

  _Channel.error(Object error) : _response = null, _error = error;

  final Object? _response;
  final Object? _error;
  final List<String> calls = [];
  final List<Object?> arguments = [];
  DiscordSocialSdkNativeHandler? handler;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    this.arguments.add(arguments);
    if (_error case final error?) throw error;
    return _response;
  }

  @override
  void setNativeHandler(DiscordSocialSdkNativeHandler? handler) {
    this.handler = handler;
  }

  Future<Object?> emit(String method, [Object? arguments]) {
    final current = handler;
    if (current == null) throw StateError('No native handler registered.');
    return current(method, arguments);
  }
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
