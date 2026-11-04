import 'package:flutter/material.dart';

/// The app's type: one bundled font family and one scale of sizes.
///
/// Every piece of text takes its size from this scale, so the interface has
/// a few sizes rather than one per widget. Nothing is under 12 px, except the
/// letters inside a tag beside a name ([appTag], [clanTag]). The font dial in
/// Accessibility then scales all of them together.
///
/// Hierarchy comes from weight and colour, not size. [FlucordTextRole] adds
/// the line height and weight that go with each size.
abstract final class FlucordType {
  /// Bundled with the app (see `assets/fonts/golos_text`), so text looks the
  /// same on Windows, macOS and Linux. A system font would exist on one of
  /// them. Its Cyrillic is drawn for interfaces: a `б` never reads as a `6`.
  static const family = 'Golos Text';

  /// Timestamps, activities, badges, group labels and hints. The smallest.
  static const caption = 12.0;

  /// Channel and member rows, buttons, menus and most interface text.
  static const label = 13.0;

  /// Message text and the composer: what people read at length. Headings
  /// use this size too, in a heavier weight.
  static const body = 14.0;

  /// Dialog and page titles.
  static const title = 20.0;

  /// The largest text, such as a channel's welcome heading.
  static const display = 24.0;

  /// The APP tag beside a bot's name. A tag is a mark, not text to read, so it
  /// sits under the caption, as Discord's does.
  static const appTag = 10.0;

  /// A clan tag beside a member's name.
  static const clanTag = 11.0;

  /// The digits in a count badge: a caption in SemiBold, each digit one width
  /// so a changing count does not shift. Interface text stops at Medium
  /// (500); a badge is a mark to spot at a glance, so it is heavier.
  static final badgeDigits = FlucordTextRole.caption.style.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Bold that a person wrote in a message (`**bold**`). It is their
  /// emphasis, not the interface's hierarchy, so it keeps SemiBold: Medium
  /// is too close to Regular to read as bold in running text.
  static const writtenBold = TextStyle(fontWeight: FontWeight.w600);

  // Golos Text's vertical metrics, as a share of the font size. From the
  // font file: 1000 units per em, ascent 980, descent 220, cap height 700.
  static const _ascent = 0.98;
  static const _descent = 0.22;
  static const _capHeight = 0.70;

  /// How far to lift lines of text, from [first] to [last], so their
  /// letters sit in the middle of what stands beside them, such as a
  /// picture.
  ///
  /// The font keeps more room above its capitals than below its baseline,
  /// so text centred by its box looks a little low next to a picture.
  static double opticalLift(FlucordTextRole first, FlucordTextRole last) {
    final below = _halfLeading(last) + _descent * last.size;
    return (roomAboveCapitals(first) - below) / 2;
  }

  /// The empty space between the top of a line in [role] and the top of its
  /// capitals. Take it off a top padding to make the gap above a title look
  /// the same as the gap beside it.
  static double roomAboveCapitals(FlucordTextRole role) =>
      _halfLeading(role) + (_ascent - _capHeight) * role.size;

  static double _halfLeading(FlucordTextRole role) =>
      (role.lineHeight - role.size * (_ascent + _descent)) / 2;

  /// Every size on the scale, smallest first.
  static const sizes = [appTag, clanTag, caption, label, body, title, display];

  /// The largest size on the scale that fits in [space], and never under
  /// [caption]. For text drawn to fill a box, such as an avatar's initial.
  static double fitting(double space) => sizes.lastWhere(
    (size) => size >= caption && size <= space,
    orElse: () => caption,
  );

  /// Material's text roles, each set to a role on the scale.
  ///
  /// Material widgets draw in these roles: a badge in `labelSmall`, helper
  /// text in `bodySmall`, a field in `bodyLarge`, a button in `labelLarge`.
  /// Material's own sizes run from 11 to 57 px, so without this they would
  /// sit off the scale.
  static TextTheme textTheme(TextTheme base) {
    TextStyle? inRole(TextStyle? style, FlucordTextRole role) =>
        style?.merge(role.style);
    return base.copyWith(
      displayLarge: inRole(base.displayLarge, FlucordTextRole.display),
      displayMedium: inRole(base.displayMedium, FlucordTextRole.display),
      displaySmall: inRole(base.displaySmall, FlucordTextRole.display),
      headlineLarge: inRole(base.headlineLarge, FlucordTextRole.display),
      headlineMedium: inRole(base.headlineMedium, FlucordTextRole.display),
      headlineSmall: inRole(base.headlineSmall, FlucordTextRole.display),
      titleLarge: inRole(base.titleLarge, FlucordTextRole.title),
      titleMedium: inRole(base.titleMedium, FlucordTextRole.heading),
      titleSmall: inRole(base.titleSmall, FlucordTextRole.heading),
      bodyLarge: inRole(base.bodyLarge, FlucordTextRole.body),
      bodyMedium: inRole(base.bodyMedium, FlucordTextRole.label),
      bodySmall: inRole(base.bodySmall, FlucordTextRole.caption),
      // A button's text is a label one weight step up.
      labelLarge: inRole(
        base.labelLarge,
        FlucordTextRole.label,
      )?.copyWith(fontWeight: FontWeight.w500),
      labelMedium: inRole(base.labelMedium, FlucordTextRole.caption),
      labelSmall: inRole(base.labelSmall, FlucordTextRole.caption),
    );
  }
}

/// A role on the type scale: a size, a line height and a weight.
///
/// Emphasis inside a role is one weight step, 400 to 500, never a size
/// change. SemiBold (600) is kept for [FlucordType.badgeDigits] and
/// [FlucordType.writtenBold].
enum FlucordTextRole {
  caption(FlucordType.caption, 16),
  label(FlucordType.label, 18),
  body(FlucordType.body, 21),
  heading(FlucordType.body, 20, FontWeight.w500),
  title(FlucordType.title, 26, FontWeight.w500),
  display(FlucordType.display, 30, FontWeight.w500);

  const FlucordTextRole(
    this.size,
    this.lineHeight, [
    this.weight = FontWeight.w400,
  ]);

  final double size;

  /// The height of one line in pixels, as a design tool gives it.
  final double lineHeight;

  final FontWeight weight;

  /// The role as a style. The extra line space is shared evenly above and
  /// below the text, as CSS does, so a 14/21 line sits where the
  /// design puts it.
  TextStyle get style => TextStyle(
    fontFamily: FlucordType.family,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// [style] one weight step up, for a title or a name inside the role.
  TextStyle get strong => style.copyWith(fontWeight: FontWeight.w500);
}
