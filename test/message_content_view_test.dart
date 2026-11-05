import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_external_link_launcher.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/message_content_view.dart';
import 'package:flucord/src/presentation/widgets/profile_card_route.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';

import 'support/contrast.dart';

void main() {
  group('a body with no markup', () {
    // Each pair draws the same text. The backslash only sends the second body
    // through the markdown parser.
    const pairs = {
      'hello world.': r'hello world\.',
      'first line.\nsecond line.':
          r'first line\.'
          '\nsecond line.',
      'Two  spaces, a colon: and 12:30, 3 + 4 = 7 (really)!':
          r'Two  spaces, a colon: and 12:30, 3 + 4 = 7 (really)\!',
      'a line long enough that it has to wrap at the width of this row, and '
              'then it keeps going for a while longer so nobody can doubt it.':
          'a line long enough that it has to wrap at the width of this row, and '
          r'then it keeps going for a while longer so nobody can doubt it\.',
    };

    for (final MapEntry(key: plain, value: parsed) in pairs.entries) {
      testWidgets('draws as it does through markdown: $plain', (tester) async {
        await tester.pumpWidget(_host(parsed));
        expect(find.byType(MarkdownBody), findsOneWidget);
        final expected = _drawnBody(tester);

        await tester.pumpWidget(_host(plain));
        expect(find.byType(MarkdownBody), findsNothing);
        final drawn = _drawnBody(tester);

        expect(drawn.text, expected.text);
        expect(drawn.style, expected.style);
        expect(drawn.textAlign, expected.textAlign);
        expect(drawn.rowSize, expected.rowSize);
        expect(drawn.textSize, expected.textSize);
      });
    }
  });

  group('a body with markup still draws as markup', () {
    const bodies = {
      '# heading': 'heading',
      '- item': 'item',
      '+ item': 'item',
      '> quote': 'quote',
      '**bold**': 'bold',
      '_slanted_': 'slanted',
      '~~gone~~': 'gone',
      '`code`': 'code',
      '||hidden||': 'hidden',
      '[docs](https://example.com)': 'docs',
      'salt &amp; pepper': 'salt & pepper',
      r'not \*bold\*': 'not *bold*',
      'title\n===': 'title',
      'title\n---': 'title',
      '    indented': 'indented',
      '<#300>': '#general',
      '<@100>': '@Mira',
    };

    for (final MapEntry(key: body, value: drawn) in bodies.entries) {
      testWidgets(body, (tester) async {
        await tester.pumpWidget(_host(body));
        await tester.pump();

        expect(_plainText(tester), contains(drawn));
        expect(_plainText(tester), isNot(contains(body)));
      });
    }

    for (final body in [
      '1. one',
      '2) two',
      'https://example.com/a',
      'www.example.com',
      '@everyone',
    ]) {
      testWidgets(body, (tester) async {
        await tester.pumpWidget(_host(body));

        expect(find.byType(MarkdownBody), findsOneWidget);
      });
    }

    testWidgets('a blank line makes two paragraphs', (tester) async {
      await tester.pumpWidget(_host('first\n\nsecond'));

      expect(find.text('first', findRichText: true), findsOneWidget);
      expect(find.text('second', findRichText: true), findsOneWidget);
    });

    testWidgets('a trailing space before a new line is dropped', (
      tester,
    ) async {
      await tester.pumpWidget(_host('first  \nsecond'));

      expect(_plainText(tester), isNot(contains('first  ')));
    });
  });

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
    expect(
      _spanWithText(tester, 'bold').style?.fontWeight,
      FlucordType.writtenBold.fontWeight,
    );
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

  testWidgets('routes a voice channel mention like any other channel', (
    tester,
  ) async {
    String? selectedChannel;
    await tester.pumpWidget(
      _host('<#301>', onSelectChannel: (id) => selectedChannel = id),
    );
    await tester.pump();

    expect(find.text('#workbench'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discord-channel-301')));

    expect(selectedChannel, '301');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a person mention opens their card and lights up under the '
      'pointer', (tester) async {
    String? opened;
    await tester.pumpWidget(
      _host('<@100>', onOpenProfile: (userId, _) => opened = userId),
    );
    final mention = find.byKey(const ValueKey('discord-user-100'));
    Color? fill() =>
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: mention,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color;
    final idle = fill();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(mention));
    await tester.pump();
    expect(fill(), isNot(idle));

    await tester.tap(mention);
    expect(opened, '100');
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

  for (final (name, theme) in [
    ('dark', FlucordTheme.dark),
    ('light', FlucordTheme.light),
  ]) {
    testWidgets('links and image fallbacks read at 4.5:1 in $name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          '[Docs](https://example.com/path) ![Map](https://example.com/m.png)',
          theme: theme,
        ),
      );

      expectReadable(theme, _spanWithText(tester, 'Docs').style?.color, 4.5);
      expectReadable(
        theme,
        tester.widget<Text>(find.text('Map')).style?.color,
        4.5,
      );
    });
  }

  for (final (name, theme) in [
    ('dark', FlucordTheme.dark),
    ('light', FlucordTheme.light),
  ]) {
    testWidgets('mentions and commands read at 4.5:1 in $name', (tester) async {
      await tester.pumpWidget(_host('<@100> </deploy:500>', theme: theme));
      await tester.pump();

      for (final label in ['@Mira', '/deploy']) {
        expectReadable(
          theme,
          tester.widget<Text>(find.text(label)).style?.color,
          4.5,
        );
      }
    });
  }

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
  OpenProfileCard? onOpenProfile,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 620,
        child: MessageContentView(
          body: body,
          workspace: _workspace,
          spaceId: null,
          linkLauncher: launcher ?? _RecordingLinkLauncher(),
          onSelectChannel: onSelectChannel ?? (_) {},
          onOpenProfile: onOpenProfile,
          now: now,
        ),
      ),
    ),
  ),
);

/// What a body draws, for comparing two bodies.
({
  String text,
  TextStyle? style,
  TextAlign textAlign,
  Size rowSize,
  Size textSize,
})
_drawnBody(WidgetTester tester) {
  final richText = find.descendant(
    of: find.byType(MessageContentView),
    matching: find.byType(RichText),
  );
  final widget = tester.widget<RichText>(richText);
  return (
    text: widget.text.toPlainText(),
    style: _styleOfText(widget.text),
    textAlign: widget.textAlign,
    rowSize: tester.getSize(find.byType(MessageContentView)),
    textSize: tester.getSize(richText),
  );
}

/// The style of the first span that holds text, with what it inherits.
TextStyle? _styleOfText(InlineSpan span, [TextStyle? inherited]) {
  final style = inherited?.merge(span.style) ?? span.style;
  if (span is TextSpan && span.text != null) return style;
  InlineSpan? child;
  span.visitDirectChildren((next) {
    child = next;
    return false;
  });
  return child == null ? style : _styleOfText(child!, style);
}

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
    ConversationChannel(
      id: '301',
      spaceId: '10',
      name: 'workbench',
      topic: 'Open voice room',
      kind: ChannelKind.voice,
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
