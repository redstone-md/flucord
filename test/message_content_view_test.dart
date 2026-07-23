import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_external_link_launcher.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/message_content_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders Markdown and resolved Discord inline entities', (
    tester,
  ) async {
    String? selectedChannel;
    final now = DateTime.utc(2026, 1, 1, 12);
    final target = now.add(const Duration(hours: 2));
    final epoch = target.millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      _host(
        '**bold** *italic* ~~gone~~ `code`\n'
        '> quoted\n'
        '<@100> <@&200> <#300> <:ship:400> '
        '<t:$epoch:R> </deploy:500> ||classified|| @everyone',
        now: now,
        onSelectChannel: (id) => selectedChannel = id,
      ),
    );
    await tester.pump();

    expect(_plainText(tester), contains('bold'));
    expect(_spanWithText(tester, 'bold').style?.fontWeight, FontWeight.w700);
    expect(_spanWithText(tester, 'italic').style?.fontStyle, FontStyle.italic);
    expect(find.text('@Mira'), findsOneWidget);
    expect(find.text('@Operator'), findsOneWidget);
    expect(find.text('#general'), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-emoji-400')), findsOneWidget);
    expect(find.text('in 2 hours'), findsOneWidget);
    expect(find.text('/deploy'), findsOneWidget);
    expect(find.text('@everyone'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discord-channel-300')));
    expect(selectedChannel, '300');

    final hidden = tester.widget<Text>(find.text('classified'));
    expect(
      hidden.style?.color,
      FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.muted,
    );
    await tester.tap(find.byKey(const ValueKey('discord-spoiler')));
    await tester.pump();
    final revealed = tester.widget<Text>(find.text('classified'));
    expect(revealed.style?.color, FlucordTheme.dark.colorScheme.onSurface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens HTTPS links and reports launcher failures', (
    tester,
  ) async {
    final launcher = _RecordingLinkLauncher();
    await tester.pumpWidget(
      _host('[Docs](https://example.com/path)', launcher: launcher),
    );

    await tester.tap(find.text('Docs', findRichText: true));
    await tester.pump();

    expect(launcher.uris.single, Uri.parse('https://example.com/path'));

    launcher.result = false;
    await tester.tap(find.text('Docs', findRichText: true));
    await tester.pump();
    expect(find.text('The link could not be opened.'), findsOneWidget);
  });

  test(
    'native launcher rejects non-web schemes before platform dispatch',
    () async {
      const launcher = NativeExternalLinkLauncher();

      expect(await launcher.open(Uri.parse('javascript:alert(1)')), isFalse);
      expect(await launcher.open(Uri.parse('file:///C:/secret.txt')), isFalse);
    },
  );
}

Widget _host(
  String body, {
  DateTime? now,
  ExternalLinkLauncher? launcher,
  ValueChanged<String>? onSelectChannel,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 620,
        child: MessageContentView(
          body: body,
          workspace: _workspace,
          linkLauncher: launcher ?? _RecordingLinkLauncher(),
          onSelectChannel: onSelectChannel ?? (_) {},
          now: now,
        ),
      ),
    ),
  ),
);

String _plainText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .join(' ');

TextSpan _spanWithText(WidgetTester tester, String text) {
  TextSpan? findSpan(InlineSpan span) {
    if (span is! TextSpan) return null;
    if (span.text == text) return span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final match = findSpan(child);
      if (match != null) return match;
    }
    return null;
  }

  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final span = widget.textSpan;
    if (span != null) {
      final match = findSpan(span);
      if (match != null) return match;
    }
  }
  throw TestFailure('No TextSpan found for $text');
}

final class _RecordingLinkLauncher implements ExternalLinkLauncher {
  bool result = true;
  final List<Uri> uris = [];

  @override
  Future<bool> open(Uri uri) async {
    uris.add(uri);
    return result;
  }
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: '10',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: '300',
      spaceId: '10',
      name: 'general',
      topic: 'Core work',
      kind: ChannelKind.text,
    ),
  ],
  roles: const [
    CommunityRole(
      id: '200',
      spaceId: '10',
      name: 'Operator',
      position: 4,
      colorValue: 0xff4c9b72,
    ),
  ],
  members: const [
    Member(
      id: '100',
      displayName: 'Mira',
      initials: 'MI',
      role: 'Operator',
      presence: Presence.online,
      colorValue: 0xff4c9b72,
    ),
  ],
  messages: const [],
  currentMemberId: '100',
);
