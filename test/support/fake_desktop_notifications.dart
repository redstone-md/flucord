import 'package:flutter/foundation.dart';

import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/platform/desktop_message_notification_controller.dart';
import 'package:flucord/src/platform/window_attention.dart';

/// The OS toast layer, as far as the desktop controllers can tell: it keeps
/// what was shown and what was taken down.
final class FakeDesktopNotificationGateway
    implements DesktopNotificationGateway {
  final List<DesktopNotificationRequest> requests = [];
  final List<String> dismissed = [];
  int initializeCount = 0;

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> dismiss(String identifier) async => dismissed.add(identifier);

  @override
  Future<void> dispose() async {}
}

/// The taskbar button, recording each flash asked of it and each stop.
final class FakeWindowAttention implements WindowAttention {
  final List<String> calls = [];

  @override
  Future<void> request() async => calls.add('flash');

  @override
  Future<void> cancel() async => calls.add('stop');
}

/// The running app as the desktop layer sees it, with a ring the test sets.
final class FakeDesktopAppSurface extends ChangeNotifier
    implements DesktopAppSurface {
  final List<ChannelLink> openedLinks = [];
  final List<bool> activeCalls = [];
  DesktopRingingCall? _ringingCall;

  /// Starts or ends a ring, and tells the listeners, as the app does.
  set ringingCall(DesktopRingingCall? value) {
    _ringingCall = value;
    notifyListeners();
  }

  @override
  DesktopRingingCall? get ringingCall => _ringingCall;

  @override
  int? get unreadChannelCount => null;

  @override
  String? get activeChannelId => null;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      const Stream.empty();

  @override
  void openChannelLink(ChannelLink link) => openedLinks.add(link);

  @override
  void handleProtocolUri(Uri uri) {}

  @override
  void setApplicationActive(bool value) => activeCalls.add(value);

  @override
  void setWindowVisible(bool value) {}

  @override
  Future<void> prepareToExit() async {}
}
