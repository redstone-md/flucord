import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/guild_access_scope.dart';
import 'package:flucord/src/presentation/widgets/message_content_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A conversation link in a message is the one outside link that routes
/// through the app's own navigation, so these tests pin where each shape of
/// it lands: in-app when the workspace holds the channel, in the browser
/// otherwise.
void main() {
  testWidgets('a link to a joined channel routes in-app', (tester) async {
    final routed = <DiscordMessageLink>[];
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      _harness(
        onOpenMessageLink: (context, link) => routed.add(link),
        launcher: launcher,
        body: 'https://discord.com/channels/forge/forge-design/m5',
      ),
    );

    await tester.tap(
      find.text(
        'https://discord.com/channels/forge/forge-design/m5',
        findRichText: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(routed, [
      const DiscordMessageLink(
        spaceId: 'forge',
        channelId: 'forge-design',
        messageId: 'm5',
      ),
    ]);
    expect(
      launcher.opened,
      isEmpty,
      reason: 'a reachable link must not also go to the browser',
    );
  });

  testWidgets('a link naming a channel of another server goes to the browser', (
    tester,
  ) async {
    final routed = <DiscordMessageLink>[];
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      _harness(
        onOpenMessageLink: (context, link) => routed.add(link),
        launcher: launcher,
        // The workspace holds forge-design under forge; naming it under
        // another guild is the mismatch under test.
        body: 'https://discord.com/channels/night/forge-design/m5',
      ),
    );

    await tester.tap(
      find.text(
        'https://discord.com/channels/night/forge-design/m5',
        findRichText: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(routed, isEmpty);
    expect(
      launcher.opened.single.toString(),
      'https://discord.com/channels/night/forge-design/m5',
    );
  });

  testWidgets(
    'a link to a channel the workspace never heard of goes external',
    (tester) async {
      final launcher = _RecordingLauncher();

      await tester.pumpWidget(
        _harness(
          onOpenMessageLink: (context, link) {},
          launcher: launcher,
          body: 'https://discord.com/channels/guild-9/chan-9/m1',
        ),
      );

      await tester.tap(
        find.text(
          'https://discord.com/channels/guild-9/chan-9/m1',
          findRichText: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(launcher.opened.single.toString(), contains('guild-9'));
    },
  );

  testWidgets('without the scope the link goes to the launcher as before', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: MessageContentView(
            body: 'https://discord.com/channels/forge/forge-design/m5',
            workspace: _workspace,
            linkLauncher: launcher,
            onSelectChannel: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.text(
        'https://discord.com/channels/forge/forge-design/m5',
        findRichText: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      launcher.opened.single.toString(),
      'https://discord.com/channels/forge/forge-design/m5',
    );
  });

  testWidgets('a scope without message routing keeps the launcher behaviour', (
    tester,
  ) async {
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      _harness(
        onOpenMessageLink: null,
        launcher: launcher,
        body: 'https://discord.com/channels/forge/forge-design/m5',
      ),
    );

    await tester.tap(
      find.text(
        'https://discord.com/channels/forge/forge-design/m5',
        findRichText: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      launcher.opened.single.toString(),
      'https://discord.com/channels/forge/forge-design/m5',
    );
  });
}

Widget _harness({
  required void Function(BuildContext, DiscordMessageLink)? onOpenMessageLink,
  required ExternalLinkLauncher launcher,
  required String body,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: GuildAccessScope(
    onOpenInvite: (context, code) {},
    onOpenMessageLink: onOpenMessageLink,
    child: Scaffold(
      body: MessageContentView(
        body: body,
        workspace: _workspace,
        linkLauncher: launcher,
        onSelectChannel: (_) {},
      ),
    ),
  ),
);

final ChatWorkspace _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'forge',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'forge-design',
      spaceId: 'forge',
      name: 'design',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
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
