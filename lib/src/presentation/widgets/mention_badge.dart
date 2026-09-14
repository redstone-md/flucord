import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

/// The one mention pill, shared by the rail, the channel sidebar and the
/// inbox so their size, radius and text weight cannot drift apart again.
class MentionBadge extends StatelessWidget {
  // The named key is forwarded to the pill Container below, not to this
  // widget, which is what the badge finders read.
  // ignore: use_key_in_widget_constructors
  const MentionBadge({required this.count, this.borderColor, Key? key})
    : _badgeKey = key;

  /// Sits on the pill Container itself rather than on this widget, which is
  /// what lets finders read the badge's decoration through it.
  final Key? _badgeKey;

  final int count;

  /// A 2px ring in the colour behind the pill, for badges that overlap an
  /// edge of that colour, like the rail's.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    key: _badgeKey,
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: FlucordColors.mention,
      borderRadius: BorderRadius.circular(9),
      border: borderColor == null
          ? null
          : Border.all(color: borderColor!, width: 2),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}
