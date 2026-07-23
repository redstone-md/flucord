import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_sticker_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:lottie/lottie.dart';

void main() {
  testWidgets('renders at most three stable sticker assets on compact width', (
    tester,
  ) async {
    final rendered = <String>[];
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _StickerApp(
        stickers: _stickers,
        assetBuilder: (_, sticker) {
          rendered.add(sticker.id);
          return ColoredBox(color: Colors.green, key: ValueKey(sticker.url));
        },
      ),
    );

    expect(rendered, ['1', '2', '3']);
    expect(find.byKey(const ValueKey('message-sticker-4')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('message-sticker-1'))),
      const Size.square(128),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes Lottie JSON and raster formats to native renderers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              Builder(
                builder: (context) => SizedBox.square(
                  dimension: 100,
                  child: buildStickerAsset(context, _stickers[1]),
                ),
              ),
              Builder(
                builder: (context) => SizedBox.square(
                  dimension: 100,
                  child: buildStickerAsset(context, _stickers[0]),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(LottieBuilder), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

class _StickerApp extends StatelessWidget {
  const _StickerApp({required this.stickers, required this.assetBuilder});

  final List<MessageSticker> stickers;
  final StickerAssetBuilder assetBuilder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MessageStickerStrip(
          stickers: stickers,
          assetBuilder: assetBuilder,
        ),
      ),
    ),
  );
}

const _stickers = [
  MessageSticker(
    id: '1',
    name: 'Signal',
    format: StickerFormat.png,
    url: 'https://invalid.example/1.png',
  ),
  MessageSticker(
    id: '2',
    name: 'Relay',
    format: StickerFormat.lottie,
    url: 'https://invalid.example/2.json',
  ),
  MessageSticker(
    id: '3',
    name: 'Deploy',
    format: StickerFormat.gif,
    url: 'https://invalid.example/3.gif',
  ),
  MessageSticker(
    id: '4',
    name: 'Hidden',
    format: StickerFormat.png,
    url: 'https://invalid.example/4.png',
  ),
];
