import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

/// The theme's field frame at [borderRadius], for a field such as search or
/// the composer that rounds its corners its own way.
///
/// Callers add their hint and icons with [InputDecoration.copyWith].
InputDecoration recessedFieldDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
}) => const InputDecoration().applyDefaults(
  FlucordTheme.recessedField(context.surfaces, radius: borderRadius),
);
