import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/trusted_domains_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/data/file_trusted_domains_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/trusted_domains.dart';
import 'package:flucord/src/presentation/widgets/message_content_view.dart';
import 'package:flucord/src/presentation/widgets/trusted_domains_scope.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('a link to another site asks first, and Visit site opens it', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      _host('https://example.com/path?q=1', launcher: launcher),
    );

    await tester.tap(
      find.text('https://example.com/path?q=1', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsOneWidget);
    expect(launcher.uris, isEmpty);

    await tester.tap(find.byKey(const ValueKey('leaving-site-visit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsNothing);
    expect(launcher.uris.single, Uri.parse('https://example.com/path?q=1'));
  });

  testWidgets('Go back closes the dialog and opens nothing', (tester) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(_host('https://example.com', launcher: launcher));

    await tester.tap(find.text('https://example.com', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsNothing);
    expect(launcher.uris, isEmpty);
  });

  testWidgets('a link to Discord, or under it, opens without asking', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      _host('https://support.discord.com/hc', launcher: launcher),
    );

    await tester.tap(
      find.text('https://support.discord.com/hc', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsNothing);
    expect(launcher.uris.single, Uri.parse('https://support.discord.com/hc'));
  });

  testWidgets('a host that only ends like Discord still asks', (tester) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      _host('https://notdiscord.com/login', launcher: launcher),
    );

    await tester.tap(
      find.text('https://notdiscord.com/login', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsOneWidget);
  });

  testWidgets('a trusted host opens without asking from then on', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();
    final repository = _MemoryTrustedDomains();
    final trust = TrustedDomainsController(repository);
    await tester.pumpWidget(
      _host('https://example.com/a', launcher: launcher, trust: trust),
    );
    final link = find.text('https://example.com/a', findRichText: true);

    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Trust example.com links from now on'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leaving-site-trust')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leaving-site-visit')));
    await tester.pumpAndSettle();

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsNothing);
    expect(launcher.uris, hasLength(2));
    expect(repository.stored.hosts, {'example.com'});
  });

  testWidgets('a masked link shows where it really goes, host first', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      _host(
        '[https://discord.com/nitro](https://discord.com@example.com/claim)',
        launcher: launcher,
      ),
    );

    await tester.tap(
      find.text('https://discord.com/nitro', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaving-site-dialog')), findsOneWidget);
    final address = tester.widget<Text>(
      find.byKey(const ValueKey('leaving-site-address')),
    );
    expect(
      address.textSpan!.toPlainText(),
      'https://discord.com@example.com/claim',
    );
    final host = _spanWithText(address.textSpan!, 'example.com');
    expect(host.style?.fontWeight, FontWeight.w500);
    expect(find.text('Trust example.com links from now on'), findsOneWidget);
  });

  test('a trusted host is still trusted after a restart', () async {
    final directory = await Directory.systemTemp.createTemp('flucord-trust');
    addTearDown(() => directory.delete(recursive: true));
    final before = TrustedDomainsController(
      FileTrustedDomainsRepository(directory: () async => directory),
    );
    await before.load();
    await before.trust(Uri.parse('https://Example.com/a'));

    final after = TrustedDomainsController(
      FileTrustedDomainsRepository(directory: () async => directory),
    );
    await after.load();

    expect(after.trusts(Uri.parse('https://example.com/b')), isTrue);
    expect(after.trusts(Uri.parse('https://other.example.com')), isFalse);
  });

  test('a damaged file trusts nothing', () async {
    final directory = await Directory.systemTemp.createTemp('flucord-trust');
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}${Platform.pathSeparator}'
      '${FileTrustedDomainsRepository.fileName}',
    ).writeAsString('{"example.com": true}');

    final read = await FileTrustedDomainsRepository(
      directory: () async => directory,
    ).load();

    expect(read.hosts, isEmpty);
  });

  testWidgets('settings list the trusted hosts and clear them, signed out '
      'too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final repository = _MemoryTrustedDomains()
      ..stored = const TrustedDomains({'example.com'});
    final trust = TrustedDomainsController(repository);
    await trust.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(
            controller: settings,
            trustedDomainsController: trust,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-chat')));
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trusted-domains-clear')));
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsNothing);
    expect(find.byKey(const ValueKey('trusted-domains-clear')), findsNothing);
    expect(trust.trusts(Uri.parse('https://example.com')), isFalse);
    expect(repository.stored.hosts, isEmpty);
  });
}

Widget _host(
  String body, {
  required ExternalLinkLauncher launcher,
  TrustedDomainsController? trust,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  // Above the navigator, as the app publishes it, so the dialog reads it.
  builder: (context, child) => TrustedDomainsScope(
    controller: trust ?? TrustedDomainsController(_MemoryTrustedDomains()),
    child: child!,
  ),
  home: Scaffold(
    body: MessageContentView(
      body: body,
      workspace: _workspace,
      spaceId: null,
      linkLauncher: launcher,
      onSelectChannel: (_) {},
    ),
  ),
);

final _workspace = ChatWorkspace(
  spaces: const [],
  channels: const [],
  members: const [],
  messages: const [],
  currentMemberId: '100000000000000001',
);

final class _MemoryTrustedDomains implements TrustedDomainsRepository {
  TrustedDomains stored = TrustedDomains.none;

  @override
  Future<TrustedDomains> load() async => stored;

  @override
  Future<void> save(TrustedDomains domains) async => stored = domains;
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> uris = [];

  @override
  Future<bool> open(Uri uri) async {
    uris.add(uri);
    return true;
  }
}

TextSpan _spanWithText(InlineSpan span, String text) {
  TextSpan? found;
  span.visitChildren((child) {
    if (child is TextSpan && child.text == text) {
      found = child;
      return false;
    }
    return true;
  });
  return found ?? (throw TestFailure('No span holds $text'));
}
