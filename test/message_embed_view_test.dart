import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/message_embed_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders Discord embed hierarchy and three inline columns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_EmbedTestApp(embed: _embed()));

    expect(find.text('Build service'), findsOneWidget);
    expect(find.text('Deploy complete'), findsOneWidget);
    expect(find.text('Windows package is ready.'), findsOneWidget);
    expect(find.text('main • 2026-07-23 03:47'), findsOneWidget);
    final firstWidth = tester
        .getSize(find.byKey(const ValueKey('embed-field-0')))
        .width;
    expect(firstWidth, lessThan(180));
    final accent = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('embed-accent')),
    );
    expect(accent.color, const Color(0xff4c9b72));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapses inline fields to one column without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(250, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_EmbedTestApp(embed: _embed(withMedia: true)));
    await tester.pumpAndSettle();

    final firstWidth = tester
        .getSize(find.byKey(const ValueKey('embed-field-0')))
        .width;
    final secondWidth = tester
        .getSize(find.byKey(const ValueKey('embed-field-1')))
        .width;
    expect(firstWidth, greaterThan(150));
    expect(firstWidth, closeTo(secondWidth, 0.1));
    expect(find.byIcon(Icons.broken_image_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

MessageEmbed _embed({bool withMedia = false}) => MessageEmbed(
  type: 'rich',
  title: 'Deploy complete',
  description: 'Windows package is ready.',
  colorValue: 0x4c9b72,
  timestamp: DateTime.utc(2026, 7, 23, 3, 47),
  author: const MessageEmbedAuthor(name: 'Build service'),
  footer: const MessageEmbedFooter(text: 'main'),
  image: withMedia
      ? const MessageEmbedMedia(
          url: 'https://invalid.example/image.png',
          width: 1200,
          height: 630,
        )
      : null,
  thumbnail: withMedia
      ? const MessageEmbedMedia(
          url: 'https://invalid.example/thumb.png',
          width: 128,
          height: 128,
        )
      : null,
  fields: const [
    MessageEmbedField(name: 'Tests', value: '91 passed', isInline: true),
    MessageEmbedField(name: 'Platform', value: 'Windows', isInline: true),
    MessageEmbedField(name: 'Mode', value: 'Release', isInline: true),
  ],
);

class _EmbedTestApp extends StatelessWidget {
  const _EmbedTestApp({required this.embed});

  final MessageEmbed embed;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MessageEmbedView(
          embed: embed,
          workspace: _workspace,
          linkLauncher: const _TestLinkLauncher(),
          onSelectChannel: (_) {},
        ),
      ),
    ),
  );
}

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
