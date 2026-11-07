import 'dart:async';

import '../domain/client_sounds.dart';
import '../platform/desktop_integration.dart';
import 'window_visible.dart';

/// Plays the message sound for each message that raises a notification.
///
/// Same rule as the toast: a message in the channel the person is looking at,
/// in a focused window, makes no sound.
final class MessageSoundCue {
  MessageSoundCue({
    required Stream<DesktopMessageNotification> notifications,
    required String? Function() activeChannelId,
    required WindowVisible window,
    required ClientSoundPlayer sounds,
  }) {
    _subscription = notifications.listen((notification) {
      final looking =
          window.focused && activeChannelId() == notification.link.channelId;
      if (!looking) sounds.play(ClientSound.message);
    });
  }

  late final StreamSubscription<DesktopMessageNotification> _subscription;

  void dispose() => unawaited(_subscription.cancel());
}
