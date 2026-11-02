import 'package:flutter/widgets.dart';

/// The corner radii. Every rounded corner in the app is one of these.
abstract final class FlucordRadius {
  /// Buttons, chips, tags, tooltips, code and small pictures.
  static const small = BorderRadius.all(Radius.circular(4));

  /// Fields, cards, popovers, menus and dialogs.
  static const medium = BorderRadius.all(mediumCorner);

  /// One corner of [medium], for a shape rounded on some sides only, such as
  /// a field joined to a bar above it.
  static const mediumCorner = Radius.circular(8);

  /// A pill or a circle, whatever the height.
  static const full = BorderRadius.all(Radius.circular(999));
}
