import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_repository_factory.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/discord_session.dart';

void main() {
  group('a credential names its account', () {
    // Made-up tokens: the first part is the base64 of a made-up id, with the
    // padding Discord leaves off, and the rest means nothing.
    test('a user token names the id in its first part', () {
      final session = DiscordDesktopUserSession(
        'MTAwMDAwMDAwMDAwMDAwMDAx.not.real',
      );
      expect(session.accountId, '100000000000000001');
    });

    test('an id of any length reads the same without padding', () {
      final session = DiscordBotSession('MTIzNDU2Nzg5MDEyMzQ1Njc4OQ.not.real');
      expect(session.accountId, '1234567890123456789');
    });

    test('a token in any other shape names nobody', () {
      for (final token in ['opaque-token', 'mfa.abc.def', 'aGVsbG8.not.real']) {
        expect(
          DiscordDesktopUserSession(token).accountId,
          isNull,
          reason: token,
        );
      }
    });
  });

  test(
    'bot sessions expose full chat capabilities without logging secrets',
    () {
      final session = DiscordBotSession('  secret-bot-token  ');

      expect(session.kind, DiscordSessionKind.botApplication);
      expect(session.transportCredential, 'secret-bot-token');
      expect(
        session.supports(DiscordSessionCapability.channelMessages),
        isTrue,
      );
      expect(
        session.supports(DiscordSessionCapability.realtimeGateway),
        isTrue,
      );
      expect(session.toString(), isNot(contains('secret-bot-token')));
    },
  );

  test('OAuth scopes do not invent chat or Gateway capabilities', () {
    final session = DiscordOAuthUserSession(
      accessToken: 'secret-oauth-token',
      scopes: const [
        'identify',
        'guilds',
        'guilds.members.read',
        'connections',
        'dm_channels.read',
      ],
      expiresAt: DateTime.utc(2026, 8),
    );

    expect(session.supports(DiscordSessionCapability.currentIdentity), isTrue);
    expect(session.supports(DiscordSessionCapability.guildDirectory), isTrue);
    expect(
      session.supports(DiscordSessionCapability.currentGuildMembership),
      isTrue,
    );
    expect(
      session.supports(DiscordSessionCapability.connectionDirectory),
      isTrue,
    );
    expect(
      session.supports(DiscordSessionCapability.directChannelDirectory),
      isTrue,
    );
    expect(session.supports(DiscordSessionCapability.channelMessages), isFalse);
    expect(session.supports(DiscordSessionCapability.realtimeGateway), isFalse);
    expect(session.toString(), isNot(contains('secret-oauth-token')));
  });

  test('desktop user sessions expose chat without logging credentials', () {
    final session = DiscordDesktopUserSession(' secret-user-session ');

    expect(session.kind, DiscordSessionKind.desktopUser);
    expect(session.transportCredential, 'secret-user-session');
    expect(session.supports(DiscordSessionCapability.channelMessages), isTrue);
    expect(session.supports(DiscordSessionCapability.realtimeGateway), isTrue);
    expect(session.toString(), isNot(contains('secret-user-session')));
  });

  test('the concrete bot repository adapter rejects OAuth before IO', () async {
    final session = DiscordOAuthUserSession(
      accessToken: 'oauth-token',
      scopes: const ['identify'],
      expiresAt: DateTime.utc(2026, 8),
    );

    await expectLater(
      const DiscordBotRepositoryFactory().create(session),
      throwsA(
        isA<UnsupportedDiscordSessionException>().having(
          (error) => error.kind,
          'kind',
          DiscordSessionKind.oauthUser,
        ),
      ),
    );
  });
}
