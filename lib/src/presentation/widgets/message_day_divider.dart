import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// Marks the place in the timeline where the calendar day changes.
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
    final line = Divider(height: 1, color: context.surfaces.border);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Expanded(child: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              MaterialLocalizations.of(context).formatFullDate(day.toLocal()),
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
    );
  }
}
