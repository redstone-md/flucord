import 'package:flutter/foundation.dart';

import '../domain/channel_link.dart';

/// One message the app says should interrupt the user: what a native toast
/// shows, and where a click lands.
final class DesktopMessageNotification {
  const DesktopMessageNotification({
    required this.identifier,
    required this.title,
    required this.body,
    required this.link,
    this.subtitle,
  });

  final String identifier;
  final String title;
  final String? subtitle;
  final String body;

  /// The channel the message arrived in, and where a click navigates. A toast
  /// for the channel the user is looking at is dropped when the window is
  /// focused.
  final ChannelLink link;
}

/// A call ringing the user, as the desktop announces it while the window is
/// not in front: a native toast and a flashing taskbar button.
final class DesktopRingingCall {
  const DesktopRingingCall({
    required this.identifier,
    required this.title,
    required this.body,
    required this.link,
    required this.showsToast,
  });

  /// One per ring, so the desktop can tell a new ring from the same one
  /// announced again.
  final String identifier;
  final String title;
  final String body;

  /// The call's conversation. A click on the toast opens it.
  final ChannelLink link;

  /// Whether the account and streamer mode allow the toast. The taskbar
  /// flashes either way, as the ring sound plays either way.
  final bool showsToast;
}

/// The running app as the desktop layer sees it: the state desktop chrome
/// reads and the actions it triggers.
///
/// The platform layer declares this interface at its own seam and the
/// application layer implements it, so no platform file reads a controller.
abstract interface class DesktopAppSurface implements Listenable {
  /// Channels with unread messages, for the tray badge. Null while no
  /// workspace is loaded, so the chrome can keep what it last showed.
  int? get unreadChannelCount;

  /// The channel the user is looking at, if any.
  String? get activeChannelId;

  /// Messages that passed the account's own interruption policy (quiet mode,
  /// mutes, the sender) and are formatted for a native toast. Whether the
  /// window is focused is a platform fact, so the platform layer makes the
  /// final call on showing one.
  Stream<DesktopMessageNotification> get messageNotifications;

  /// The call ringing the user right now, or null. A ring that starts or
  /// ends is announced to listeners. As with messages, whether the window is
  /// in front is for the platform layer to judge.
  DesktopRingingCall? get ringingCall;

  /// Navigates to a channel. A link that arrives before the workspace is
  /// loaded is held and applied once the workspace exists.
  void openChannelLink(ChannelLink link);

  /// Handles a flucord:// URI that is not a channel link, such as an OAuth
  /// callback.
  void handleProtocolUri(Uri uri);

  /// Marks the app active or inactive for the chat's read state. Window
  /// focus drives it.
  void setApplicationActive(bool value);

  /// Tells whether anything of the window is on screen: minimized or hidden
  /// windows are not, unfocused ones still are. Watched sessions suspend on
  /// it (ADR-0003).
  void setWindowVisible(bool value);

  /// Finishes what the app still holds, before the process ends. A native exit
  /// does not unmount the widgets, so nothing else closes the session then.
  Future<void> prepareToExit();
}

abstract interface class DesktopIntegration {
  Future<void> initialize();

  void attach(DesktopAppSurface surface);

  Future<void> dispose();
}
