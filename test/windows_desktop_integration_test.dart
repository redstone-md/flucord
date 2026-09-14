import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/platform/windows_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<MethodCall> autoUpdaterCalls;
  late List<MethodCall> trayCalls;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    autoUpdaterCalls = [];
    trayCalls = [];
    for (final entry in {
      'window_manager': (MethodCall call) async {
        if (call.method == 'isMinimized' || call.method == 'isFocused') {
          return false;
        }
        return null;
      },
      'local_notifier': (MethodCall call) async =>
          call.method == 'setup' ? true : null,
      'tray_manager': (MethodCall call) async {
        trayCalls.add(call);
        return null;
      },
      'dev.leanflutter.plugins/protocol_handler': (MethodCall call) async {
        return call.method == 'getInitialUrl' ? '' : null;
      },
      'dev.leanflutter.plugins/auto_updater': (MethodCall call) async {
        autoUpdaterCalls.add(call);
        return null;
      },
    }.entries) {
      messenger.setMockMethodCallHandler(MethodChannel(entry.key), entry.value);
    }
    // The updater and the protocol handler listen on event channels; a
    // silent success keeps those subscriptions quiet.
    for (final channel in [
      'dev.leanflutter.plugins/protocol_handler_event',
      'dev.leanflutter.plugins/auto_updater_event',
    ]) {
      messenger.setMockMessageHandler(channel, (message) async {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      });
    }
    // The tray icon is materialized from a bundled asset.
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      return ByteData.view(Uint8List.fromList([1, 0, 0]).buffer);
    });
  });

  tearDown(() {
    for (final channel in [
      'window_manager',
      'local_notifier',
      'tray_manager',
      'dev.leanflutter.plugins/protocol_handler',
      'dev.leanflutter.plugins/auto_updater',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    for (final channel in [
      'dev.leanflutter.plugins/protocol_handler_event',
      'dev.leanflutter.plugins/auto_updater_event',
      'flutter/assets',
    ]) {
      messenger.setMockMessageHandler(channel, null);
    }
  });

  Map<Object?, Object?>? trayItem(String key) {
    final menuCall = trayCalls.lastWhere(
      (call) => call.method == 'setContextMenu',
    );
    final menu = menuCall.arguments as Map<Object?, Object?>;
    final items = (menu['menu'] as Map<Object?, Object?>)['items'] as List;
    for (final item in items) {
      if ((item as Map<Object?, Object?>)['key'] == key) return item;
    }
    return null;
  }

  test(
    'a configured appcast feeds the updater and enables the tray action',
    () async {
      final integration = WindowsDesktopIntegration(
        updater: AutoDesktopUpdater(
          feedUrl: 'https://updates.example.com/appcast.xml',
        ),
      );
      addTearDown(integration.dispose);

      await integration.initialize();

      expect(autoUpdaterCalls, hasLength(2));
      expect(autoUpdaterCalls[0].method, 'setFeedURL');
      expect(autoUpdaterCalls[0].arguments, {
        'feedURL': 'https://updates.example.com/appcast.xml',
      });
      expect(autoUpdaterCalls[1].method, 'setScheduledCheckInterval');
      expect(autoUpdaterCalls[1].arguments, {'interval': 86400});
      expect(trayItem('check_updates'), isNotNull);
      expect(trayItem('check_updates')!['disabled'], isFalse);
      expect(trayItem('quit'), isNotNull);
    },
  );

  test(
    'without an appcast the updater stays quiet and the action is disabled',
    () async {
      final integration = WindowsDesktopIntegration();
      addTearDown(integration.dispose);

      await integration.initialize();

      expect(autoUpdaterCalls, isEmpty);
      expect(trayItem('check_updates'), isNotNull);
      expect(trayItem('check_updates')!['disabled'], isTrue);
    },
  );
}
