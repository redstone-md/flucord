import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_call_alert_controller.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

import 'support/fake_desktop_notifications.dart';

const _dm = ChannelLink(spaceId: '@me', channelId: 'dm-mira');

DesktopRingingCall _ring({bool showsToast = true}) => DesktopRingingCall(
  identifier: 'flucord-call-dm-mira',
  title: 'Incoming call',
  body: 'Mira is calling',
  link: _dm,
  showsToast: showsToast,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDesktopNotificationGateway gateway;
  late FakeWindowAttention attention;
  late FakeDesktopAppSurface surface;
  late bool focused;
  late int windowShown;
  late DesktopCallAlertController controller;

  setUp(() {
    gateway = FakeDesktopNotificationGateway();
    attention = FakeWindowAttention();
    surface = FakeDesktopAppSurface();
    focused = false;
    windowShown = 0;
    controller = DesktopCallAlertController(
      isFocused: () async => focused,
      gateway: gateway,
      attention: attention,
    );
    controller.attach(surface: surface, showWindow: () async => windowShown++);
    addTearDown(controller.dispose);
    addTearDown(surface.dispose);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a ring behind other windows shows a toast and flashes', () async {
    surface.ringingCall = _ring();
    await settle();

    final request = gateway.requests.single;
    expect(request.identifier, 'flucord-call-dm-mira');
    expect(request.title, 'Incoming call');
    expect(request.body, 'Mira is calling');
    expect(attention.calls, ['flash']);

    // The app announces every change it sees, and the ring is still the same
    // one: it is not shown twice.
    surface.ringingCall = _ring();
    await settle();
    expect(gateway.requests, hasLength(1));
    expect(attention.calls, ['flash']);
  });

  test('a ring in a focused window stays in the window', () async {
    focused = true;

    surface.ringingCall = _ring();
    await settle();

    expect(gateway.requests, isEmpty);
    expect(attention.calls, isEmpty);
  });

  test('a ring follows the window losing and gaining the focus', () async {
    focused = true;
    surface.ringingCall = _ring();
    await settle();
    expect(gateway.requests, isEmpty);

    focused = false;
    controller.windowFocusChanged(focused: false);
    await settle();
    expect(gateway.requests, hasLength(1));
    expect(attention.calls, ['flash']);

    focused = true;
    controller.windowFocusChanged(focused: true);
    await settle();
    expect(gateway.dismissed, ['flucord-call-dm-mira']);
    expect(attention.calls, ['flash', 'stop']);
  });

  test('clicking the toast brings the window up on the call', () async {
    surface.ringingCall = _ring();
    await settle();

    await gateway.requests.single.onClick();

    expect(windowShown, 1);
    expect(surface.openedLinks, [_dm]);
  });

  test('the toast and the flash go when the ring ends', () async {
    surface.ringingCall = _ring();
    await settle();

    surface.ringingCall = null;
    await settle();

    expect(gateway.dismissed, ['flucord-call-dm-mira']);
    expect(attention.calls, ['flash', 'stop']);
  });

  test('a toast the account turned off still flashes the taskbar', () async {
    surface.ringingCall = _ring(showsToast: false);
    await settle();

    expect(gateway.requests, isEmpty);
    expect(attention.calls, ['flash']);
  });

  test('a ring that ends while focus is read raises nothing', () async {
    surface.ringingCall = _ring();
    surface.ringingCall = null;
    await settle();

    expect(gateway.requests, isEmpty);
    expect(attention.calls, isEmpty);
  });
}
