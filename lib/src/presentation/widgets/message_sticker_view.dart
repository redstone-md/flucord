import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

typedef StickerAssetBuilder =
    Widget Function(BuildContext context, MessageSticker sticker);

class MessageStickerStrip extends StatelessWidget {
  const MessageStickerStrip({
    required this.stickers,
    this.assetBuilder = buildStickerAsset,
    super.key,
  });

  final List<MessageSticker> stickers;
  final StickerAssetBuilder assetBuilder;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final sticker in stickers.take(3))
          Semantics(
            label: '${sticker.name} sticker',
            image: true,
            child: Tooltip(
              message: sticker.name,
              child: SizedBox.square(
                key: ValueKey('message-sticker-${sticker.id}'),
                dimension: stickers.length == 1 ? 160 : 128,
                child: RepaintBoundary(child: assetBuilder(context, sticker)),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget buildStickerAsset(BuildContext context, MessageSticker sticker) {
  final fallback = _StickerFallback(name: sticker.name);
  if (sticker.isLottie) {
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Lottie.network(
          sticker.url,
          fit: BoxFit.contain,
          repeat: true,
          backgroundLoading: true,
          errorBuilder: (_, _, _) => fallback,
        ),
      ],
    );
  }
  return Image.network(
    sticker.url,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : fallback,
    errorBuilder: (_, _, _) => fallback,
  );
}

class _StickerFallback extends StatelessWidget {
  const _StickerFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.surfaces.border),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_emotions_outlined, color: context.surfaces.muted),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}
