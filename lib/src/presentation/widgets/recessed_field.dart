import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

/// The frame of a field people type in, such as search or the composer: the
/// inset colour, a 1 px border and the theme's focus ring. It sits darker
/// than what is around it, so it reads as the place to type.
///
/// Callers add their hint and icons with [InputDecoration.copyWith].
InputDecoration recessedFieldDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
}) {
  final surfaces = context.surfaces;
  final focusRing = Theme.of(
    context,
  ).inputDecorationTheme.focusedBorder!.borderSide;
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: borderRadius, borderSide: side);
  final resting = outline(BorderSide(color: surfaces.border));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: surfaces.inset,
    border: resting,
    enabledBorder: resting,
    disabledBorder: resting,
    focusedBorder: outline(focusRing),
  );
}
