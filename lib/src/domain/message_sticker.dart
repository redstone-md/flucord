part of 'chat_models.dart';

enum StickerFormat {
  unknown(0),
  png(1),
  apng(2),
  lottie(3),
  gif(4);

  const StickerFormat(this.discordValue);

  final int discordValue;

  static StickerFormat fromDiscordValue(int? value) {
    for (final format in values) {
      if (format.discordValue == value) return format;
    }
    return unknown;
  }
}

final class MessageSticker {
  const MessageSticker({
    required this.id,
    required this.name,
    required this.format,
    required this.url,
  });

  final String id;
  final String name;
  final StickerFormat format;
  final String url;

  bool get isLottie => format == StickerFormat.lottie;
  bool get isAnimated =>
      format == StickerFormat.apng ||
      format == StickerFormat.lottie ||
      format == StickerFormat.gif;
}
