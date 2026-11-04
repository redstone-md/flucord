import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds every [FlucordIcon] that draws [icon], the way `find.byIcon` finds a
/// Material icon.
Finder findFlucordIcon(FlucordIconData icon) => find.byWidgetPredicate(
  (widget) => widget is FlucordIcon && widget.icon == icon,
  description: 'FlucordIcon drawing $icon',
);
