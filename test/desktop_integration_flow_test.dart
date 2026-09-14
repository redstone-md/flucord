import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/platform/desktop_integration_flow.dart';
import 'package:flucord/src/platform/desktop_protocol_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<MethodCall> windowCalls;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    windowCalls = [];
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      windowCalls.add(call);
      if (call.method == 'isMinimized' || call.method == 'isFocused') {
        return false;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('local_notifier'),
      (call) async => call.method == 'setup' ? true : null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      return null;
    });
    // The tray icon is materialized from a bundled asset, so the asset
    // bundle must answer.
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      return ByteData.view(Uint8List.fromList([1, 0, 0]).buffer);
    });
  });

  tearDown(() {
    for (final channel in [
      'window_manager',
      'local_notifier',
      'tray_manager',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<void> sendWindowEvent(String eventName) {
    return messenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onEvent', {'eventName': eventName}),
      ),
      (_) {},
    );
  }

  test('launch URLs route without raising the window', () async {
    final intake = _FakeIntake(const ['flucord://channels/guild-1/channel-9']);
    final flow = DesktopIntegrationFlow(protocolIntake: intake);
    addTearDown(flow.dispose);

    await flow.initialize();
    expect(windowCalls.map((call) => call.method), [
      'ensureInitialized',
      'setPreventClose',
    ]);

    final surface = _RecordingSurface();
    flow.attach(surface);
    expect(surface.openedChannels, ['channel-9']);
    expect(surface.activeCalls, isEmpty);
  });

  test('a URL that arrives later raises the window and routes', () async {
    final intake = _FakeIntake(const []);
    final flow = DesktopIntegrationFlow(protocolIntake: intake);
    addTearDown(flow.dispose);
    await flow.initialize();

    final surface = _RecordingSurface();
    flow.attach(surface);
    intake.onUrl?.call('flucord://channels/guild-1/channel-2');
    await Future<void>.delayed(Duration.zero);

    expect(
      windowCalls.map((call) => call.method),
      containsAllInOrder(['isMinimized', 'show', 'focus']),
    );
    expect(surface.openedChannels, ['channel-2']);
    expect(surface.activeCalls, [true]);
  });

  test('window focus and blur drive the surface active state', () async {
    final intake = _FakeIntake(const []);
    final flow = DesktopIntegrationFlow(protocolIntake: intake);
    addTearDown(flow.dispose);
    await flow.initialize();

    final surface = _RecordingSurface();
    flow.attach(surface);

    await sendWindowEvent('focus');
    await sendWindowEvent('blur');

    expect(surface.activeCalls, [true, false]);
  });

  test(
    'coming back from minimized is visible however the window returns',
    () async {
      final intake = _FakeIntake(const []);
      final flow = DesktopIntegrationFlow(protocolIntake: intake);
      addTearDown(flow.dispose);
      await flow.initialize();

      final surface = _RecordingSurface();
      flow.attach(surface);

      // A maximized window minimized and brought back reports `maximize`, not
      // `restore`, and whatever brought it back gave it the focus. Either is
      // on screen again.
      await sendWindowEvent('minimize');
      await sendWindowEvent('maximize');
      await sendWindowEvent('minimize');
      await sendWindowEvent('focus');

      expect(surface.visibilityCalls, [false, true, false, true]);
    },
  );

  test('closing the window hides to tray and marks the app inactive', () async {
    final intake = _FakeIntake(const []);
    final flow = DesktopIntegrationFlow(protocolIntake: intake);
    addTearDown(flow.dispose);
    await flow.initialize();
    // The tray became ready, so close is intercepted.
    expect(windowCalls.map((call) => call.method), contains('setPreventClose'));

    final surface = _RecordingSurface();
    flow.attach(surface);

    await sendWindowEvent('close');

    expect(windowCalls.map((call) => call.method), contains('hide'));
    expect(surface.activeCalls, [false]);
  });

  test('dispose tears the sub-modules down once', () async {
    final intake = _FakeIntake(const []);
    final flow = DesktopIntegrationFlow(protocolIntake: intake);
    await flow.initialize();

    await flow.dispose();
    await flow.dispose();

    expect(intake.disposed, isTrue);
  });
}

final class _FakeIntake implements DesktopProtocolIntake {
  _FakeIntake(this.launchUrls);

  final List<String> launchUrls;
  void Function(String url)? onUrl;
  bool disposed = false;

  @override
  Future<List<String>> start(void Function(String url) onUrl) async {
    this.onUrl = onUrl;
    return launchUrls;
  }

  @override
  void dispose() => disposed = true;
}

final class _RecordingSurface extends ChangeNotifier
    implements DesktopAppSurface {
  final List<bool> activeCalls = [];
  final List<bool> visibilityCalls = [];
  final List<String> openedChannels = [];
  final List<Uri> protocolUris = [];

  @override
  int? get unreadChannelCount => null;

  @override
  String? get activeChannelId => null;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      const Stream.empty();

  @override
  void openChannelLink(ChannelLink link) => openedChannels.add(link.channelId);

  @override
  void handleProtocolUri(Uri uri) => protocolUris.add(uri);

  @override
  void setApplicationActive(bool value) => activeCalls.add(value);

  @override
  void setWindowVisible(bool value) => visibilityCalls.add(value);
}
