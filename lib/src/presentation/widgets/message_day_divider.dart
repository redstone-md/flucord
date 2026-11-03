import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// Marks the place in the timeline where the calendar day changes: a thin
/// line on each side of the date. Rows show only the time, so this is where
/// the date lives.
class MessageDayDivider extends StatelessWidget {
  const MessageDayDivider({required this.day, super.key});

  /// Any moment on the day this divider opens.
  final DateTime day;

  /// Whether two neighbouring messages fall on different days of the reader's
  /// own calendar. Compares calendar fields rather than a duration, so a
  /// daylight saving change cannot move the line.
  static bool between(DateTime previous, DateTime current) =>
      !DateUtils.isSameDay(previous.toLocal(), current.toLocal());

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final line = Divider(height: 1, thickness: 1, color: surfaces.border);
    // The next message adds its own group gap below, so the space reads the
    // same above and below the line.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          Expanded(child: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              MaterialLocalizations.of(context).formatFullDate(day.toLocal()),
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.captionText,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
    );
  }
}
