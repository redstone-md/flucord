abstract final class DiscordColor {
  static int? parseHex(String source) {
    final value = source.startsWith('#') ? source.substring(1) : source;
    final rgb = int.tryParse(value, radix: 16);
    return rgb == null ? null : 0xff000000 | rgb;
  }
}
