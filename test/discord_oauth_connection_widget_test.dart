import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

void main() {
  testWidgets('links and unlinks an OAuth account without changing chat mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _OAuthGateway();

    await tester.pumpWidget(
      FlucordApp.demo(discordOAuthAccountGateway: gateway),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(find.text('Discord account'), findsOneWidget);
    expect(find.text('No Discord account linked.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();

    expect(find.text('Jack · 2 servers'), findsOneWidget);
    expect(find.text('Demo workspace active'), findsOneWidget);
    expect(gateway.authorizeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('unlink-discord-account')));
    await tester.pumpAndSettle();

    expect(find.text('No Discord account linked.'), findsOneWidget);
    expect(gateway.clearCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps both connection lanes scrollable on a compact desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(discordOAuthAccountGateway: _OAuthGateway()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link-discord-account')), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-bot-token')), findsOneWidget);
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
  int authorizeCalls = 0;
  int clearCalls = 0;
  Uri? handledUri;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() async {
    authorizeCalls++;
    return const DiscordOAuthAccount(
      id: '123456789012345678',
      username: 'jack',
      displayName: 'Jack',
      guildCount: 2,
    );
  }

  @override
  Future<void> clear() async => clearCalls++;

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
