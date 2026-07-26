import 'package:flutter/widgets.dart';

import '../../domain/user_settings.dart';
import 'user_settings_scope.dart';

/// Renders the clock beside a message.
///
/// Discord stores the hour cycle on the account, so the same message reads
/// `21:04` on one device and `9:04 PM` on the next. Keeping the rule here
/// rather than inside the message row means the account setting has exactly
/// one place to reach, and that place can be tested without a widget tree.
abstract final class MessageTimestamp {
  static String of(BuildContext context, DateTime value) =>
      format(value, UserSettingsScope.hourCycleOf(context));

  static String format(DateTime value, TimestampHourCycle cycle) {
    final minute = value.minute.toString().padLeft(2, '0');
    if (cycle != TimestampHourCycle.hour12) {
      // `auto` follows the platform's locale in Discord's renderer. Flucord
      // ships one language and no locale data, so it resolves to the 24-hour
      // clock it has always drawn rather than to a guess at the OS setting.
      return '${value.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }
}
