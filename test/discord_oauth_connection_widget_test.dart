import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

void main() {
  testWidgets('reveals bot credentials only in an explicit developer build', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: _OAuthGateway(),
        enableBotTransport: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('developer-bot-transport')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('discord-bot-token')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('developer-bot-transport')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discord-bot-token')), findsOneWidget);
    expect(find.text('Application bot token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forwards desktop protocol callbacks to OAuth', (tester) async {
    final gateway = _OAuthGateway();
    final desktop = _DesktopIntegration();

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: gateway,
        desktopIntegration: desktop,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    desktop.emit(Uri.parse('flucord://oauth/discord/callback?code=x'));
    await tester.pump();

    expect(
      gateway.handledUri,
      Uri.parse('flucord://oauth/discord/callback?code=x'),
    );
  });
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  Uri? handledUri;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() async {
    return DiscordOAuthAccount(
      id: '123456789012345678',
      username: 'jack',
      displayName: 'Jack',
      guilds: const [],
      connections: [
        DiscordOAuthConnection(
          id: 'spotify-1',
          name: 'jack.fm',
          type: 'spotify',
          verified: true,
          showActivity: true,
          visibility: 1,
        ),
        DiscordOAuthConnection(
          id: 'github-1',
          name: 'redstone-md',
          type: 'github',
        ),
      ],
    );
  }

  @override
  Future<void> clear() async {}

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) => throw StateError('Guild membership is not part of this test.');

  @override
  void dispose() {}

  @override
  Future<bool> handleRedirect(Uri uri) async {
    handledUri = uri;
    return true;
  }

  @override
  Future<DiscordOAuthAccount?> restore() async => null;
}

final class _DesktopIntegration implements DesktopIntegration {
  void Function(Uri uri)? _onProtocolUri;

  @override
  void attach({
    required ChatController chatController,
    required WorkspaceController workspaceController,
    required void Function(Uri uri) onProtocolUri,
  }) {
    _onProtocolUri = onProtocolUri;
  }

  void emit(Uri uri) => _onProtocolUri!(uri);

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}
}
