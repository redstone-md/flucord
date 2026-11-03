import 'package:flutter/material.dart';

import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// The one count pill in the app: unread mentions, message requests, people
/// in a call. Every count uses it, so they cannot drift apart in size, shape
/// or weight.
///
/// It is 16 px high and at least 16 px wide, red by default.
class CountBadge extends StatelessWidget {
  const CountBadge({
    required this.count,
    this.ring,
    this.color,
    this.textColor,
    super.key,
  });

  static const height = 16.0;
  static const _ringWidth = 2.0;

  final int count;

  /// The colour behind the badge, drawn as a 2 px ring outside the pill. It
  /// cuts the badge out of an edge it overlaps, such as a server tile. A
  /// badge inline in a row has nothing to cut out of and leaves it null.
  final Color? ring;

  /// The fill, danger by default. A count that is not a call to action, such
  /// as people in a call, takes a neutral one.
  final Color? color;

  final Color? textColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? context.surfaces.danger,
      borderRadius: FlucordRadius.full,
      border: ring == null
          ? null
          : Border.all(
              color: ring!,
              width: _ringWidth,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
    ),
    child: Container(
      constraints: const BoxConstraints(minWidth: height),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        widthFactor: 1,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: FlucordTextRole.caption.style.copyWith(
            color: textColor ?? Colors.white,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}
