import 'dart:async';

import '../domain/client_sounds.dart';
import '../platform/desktop_integration.dart';
import '../platform/desktop_message_notification_controller.dart';
import 'window_visible.dart';

/// Plays the message sound for each message that raises a notification.
///
/// The toast's own rule, [isReadingChannel]: a message in the channel the
/// person is reading, in a focused window, makes no sound.
final class MessageSoundCue {
  MessageSoundCue({
    required Stream<DesktopMessageNotification> notifications,
    required String? Function() activeChannelId,
    required WindowVisible window,
    required ClientSoundPlayer sounds,
  }) {
    _subscription = notifications.listen((notification) {
      final reading = isReadingChannel(
        notification.link.channelId,
        activeChannelId: activeChannelId(),
        focused: window.focused,
      );
      if (!reading) sounds.play(ClientSound.message);
    });
  }

  late final StreamSubscription<DesktopMessageNotification> _subscription;

  void dispose() => unawaited(_subscription.cancel());
}
