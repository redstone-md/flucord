import 'package:flutter/widgets.dart';

/// The corner radii. Every rounded corner in the app is one of these.
abstract final class FlucordRadius {
  /// Buttons, chips, tags, tooltips, code and small pictures.
  static const small = BorderRadius.all(Radius.circular(4));

  /// Fields, cards, popovers, menus and dialogs.
  static const medium = BorderRadius.all(Radius.circular(8));

  /// A pill or a circle, whatever the height.
  static const full = BorderRadius.all(Radius.circular(999));
}
