/// A colour as Discord sends it: 0xRRGGBB, with no alpha.
extension type const DiscordRgb(int rgb) {
  /// The same colour, fully opaque, as an ARGB value for `Color`.
  int get opaque => 0xff000000 | (rgb & 0x00ffffff);
}
