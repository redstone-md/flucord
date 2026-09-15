import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/guild_access_scope.dart';
import 'package:flucord/src/presentation/widgets/message_content_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an invite link in a message opens the join surface', (
    tester,
  ) async {
    final opened = <String>[];
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: GuildAccessScope(
          onOpenInvite: (context, code) {
            opened.add(code);
            Navigator.of(context).pop();
          },
          onOpenMessageLink: null,
          child: Scaffold(
            body: MessageContentView(
              body: 'https://discord.gg/aurora',
              workspace: _workspace,
              linkLauncher: launcher,
              onSelectChannel: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.text('https://discord.gg/aurora', findRichText: true),
    );

    await tester.pumpAndSettle();

    expect(opened, ['aurora']);
    expect(
      launcher.opened,
      isEmpty,
      reason: 'the invite must not also go to the browser',
    );
  });

  testWidgets('without the scope the link goes to the launcher as before', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: MessageContentView(
            body: 'https://discord.gg/aurora',
            workspace: _workspace,
            linkLauncher: launcher,
            onSelectChannel: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.text('https://discord.gg/aurora', findRichText: true),
    );

    await tester.pumpAndSettle();

    expect(launcher.opened.single.toString(), 'https://discord.gg/aurora');
  });
}

final ChatWorkspace _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'forge',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [],
  members: const [],
  messages: const [],
  currentMemberId: 'jack',
);

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}
