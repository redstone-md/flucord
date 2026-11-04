import 'package:flutter/widgets.dart';

/// The corner radii. Every rounded corner in the app is one of these.
abstract final class FlucordRadius {
  /// Tags, chips, tooltips, code and small pictures.
  static const small = BorderRadius.all(Radius.circular(4));

  /// Rows, buttons, icon buttons and small fields.
  static const control = BorderRadius.all(Radius.circular(6));

  /// The composer, cards and toolbars.
  static const medium = BorderRadius.all(mediumCorner);

  /// One corner of [medium], for a shape rounded on some sides only, such as
  /// a field joined to a bar above it.
  static const mediumCorner = Radius.circular(8);

  /// The canvas card, server tiles, and rows inside a menu.
  static const large = BorderRadius.all(Radius.circular(12));

  /// A card that holds a picture with [medium] corners 8 in from its edge,
  /// such as an activity or a server card. 8 + 8, so the two corners stay
  /// parallel.
  static const framed = BorderRadius.all(Radius.circular(16));

  /// Anything that opens over the interface: dialogs, menus, popovers,
  /// pickers, profile cards and the incoming call card.
  static const overlay = BorderRadius.all(Radius.circular(16));

  /// A pill or a circle, whatever the height.
  static const full = BorderRadius.all(Radius.circular(999));
}
