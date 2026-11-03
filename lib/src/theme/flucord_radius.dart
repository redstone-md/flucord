import 'package:flutter/widgets.dart';

/// The corner radii. Every rounded corner in the app is one of these.
abstract final class FlucordRadius {
  /// Tags, chips, tooltips, code and small pictures.
  static const small = BorderRadius.all(Radius.circular(4));

  /// Rows, buttons, icon buttons and small fields.
  static const control = BorderRadius.all(Radius.circular(6));

  /// The composer, cards, menus, toolbars, popovers and dialogs.
  static const medium = BorderRadius.all(mediumCorner);

  /// One corner of [medium], for a shape rounded on some sides only, such as
  /// a field joined to a bar above it.
  static const mediumCorner = Radius.circular(8);

  /// The canvas card and server tiles.
  static const large = BorderRadius.all(Radius.circular(12));

  /// A pill or a circle, whatever the height.
  static const full = BorderRadius.all(Radius.circular(999));
}
