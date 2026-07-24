import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_repository_factory.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/discord_session.dart';

void main() {
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
