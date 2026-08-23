import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/platform/desktop_message_notification_controller.dart';

DesktopMessageNotification _notification({
  required String identifier,
  ChannelLink link = const ChannelLink(
    spaceId: 'night',
    channelId: 'night-ops',
  ),
}) => DesktopMessageNotification(
  identifier: identifier,
  title: 'Mira - #night-ops',
  subtitle: 'Night City',
  body: 'Native message delivery',
  link: link,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shows a toast and activates its channel on click', () async {
    final gateway = _NotificationGateway();
    final controller = DesktopMessageNotificationController(
      isFocused: () async => false,
      gateway: gateway,
    );
    final surface = _SurfaceStub();
    var windowShown = 0;
    addTearDown(controller.dispose);
    addTearDown(surface.dispose);
    await controller.initialize();
    controller.attach(surface: surface, showWindow: () async => windowShown++);

    await controller.notify(_notification(identifier: 'flucord-toast-1'));

    expect(gateway.initializeCount, 1);
    expect(gateway.requests, hasLength(1));
    final request = gateway.requests.single;
    expect(request.identifier, 'flucord-toast-1');
    expect(request.title, 'Mira - #night-ops');
    expect(request.subtitle, 'Night City');
    expect(request.body, 'Native message delivery');

    await request.onClick();
    expect(windowShown, 1);
    expect(
      surface.openedLinks.single,
      const ChannelLink(spaceId: 'night', channelId: 'night-ops'),
    );
  });

  test('drops the toast for the focused active channel only', () async {
    final gateway = _NotificationGateway();
    var focused = true;
    final controller = DesktopMessageNotificationController(
      isFocused: () async => focused,
      gateway: gateway,
    );
    final surface = _SurfaceStub()..activeChannel = 'night-ops';
    addTearDown(controller.dispose);
    addTearDown(surface.dispose);
    await controller.initialize();
    controller.attach(surface: surface, showWindow: () async {});

    // The message's channel is on screen and the window is focused.
    await controller.notify(_notification(identifier: 'visible'));
    expect(gateway.requests, isEmpty);

    // Blurred, the same message interrupts again.
    focused = false;
    await controller.notify(_notification(identifier: 'blurred'));
    expect(gateway.requests, hasLength(1));

    // Focused, a message for another channel still interrupts.
    await controller.notify(
      _notification(
        identifier: 'elsewhere',
        link: const ChannelLink(spaceId: 'night', channelId: 'general'),
      ),
    );
    expect(gateway.requests, hasLength(2));
  });

  test('stays silent while streamer mode is on', () async {
    final gateway = _NotificationGateway();
    var streaming = true;
    final controller = DesktopMessageNotificationController(
      isFocused: () async => false,
      gateway: gateway,
      isSuppressed: () => streaming,
    );
    final surface = _SurfaceStub();
    addTearDown(controller.dispose);
    addTearDown(surface.dispose);
    await controller.initialize();
    controller.attach(surface: surface, showWindow: () async {});

    await controller.notify(_notification(identifier: 'streamer'));
    expect(gateway.requests, isEmpty);

    // Read per message: the mode can go on and off between two of them.
    streaming = false;
    await controller.notify(_notification(identifier: 'off-stream'));
    expect(gateway.requests, hasLength(1));
  });

  test('shows what the surface stream delivers after attach', () async {
    final gateway = _NotificationGateway();
    final controller = DesktopMessageNotificationController(
      isFocused: () async => false,
      gateway: gateway,
    );
    final surface = _SurfaceStub();
    addTearDown(controller.dispose);
    addTearDown(surface.dispose);
    await controller.initialize();
    controller.attach(surface: surface, showWindow: () async {});

    surface.emit(_notification(identifier: 'flucord-streamed'));
    await Future<void>.delayed(Duration.zero);

    expect(gateway.requests, hasLength(1));
    expect(gateway.requests.single.identifier, 'flucord-streamed');
  });
}

final class _SurfaceStub extends ChangeNotifier implements DesktopAppSurface {
  final StreamController<DesktopMessageNotification> _notifications =
      StreamController.broadcast();
  final List<ChannelLink> openedLinks = [];
  String? activeChannel;

  void emit(DesktopMessageNotification notification) =>
      _notifications.add(notification);

  @override
  int? get unreadChannelCount => null;

  @override
  String? get activeChannelId => activeChannel;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      _notifications.stream;

  @override
  void openChannelLink(ChannelLink link) => openedLinks.add(link);

  @override
  void handleProtocolUri(Uri uri) {}

  @override
  void setApplicationActive(bool value) {}
}

final class _NotificationGateway implements DesktopNotificationGateway {
  final List<DesktopNotificationRequest> requests = [];
  int initializeCount = 0;

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> dispose() async {}
}
