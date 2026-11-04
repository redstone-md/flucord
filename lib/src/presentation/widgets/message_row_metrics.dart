/// The sizes of a message row. Server messages and native DM messages both
/// read them, so the two rows line up.
abstract final class MessageRowMetrics {
  /// Space above a new author's message, outside the highlight. Compact
  /// density shrinks it, as Discord's group spacing setting does.
  static const groupGap = 10.0;
  static const compactGroupGap = 4.0;

  /// Space inside the highlight, on the left and right.
  static const inline = 16.0;

  /// Space inside the highlight, above and below: the same on both sides.
  static const block = 4.0;
  static const followUpBlock = 1.0;
  static const mentionBlock = 7.0;

  static const avatarSize = 40.0;
  static const avatarGap = 12.0;
  static const nameRowHeight = 18.0;

  /// Space between a reply line and the name row under it.
  static const replyGap = 4.0;

  /// How far the toolbar rises above the highlight's top edge.
  static const barRise = 16.0;

  static const hoverAlpha = 0.025;
  static const mentionAlpha = 0.08;
  static const mentionBarWidth = 2.0;
}
