import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/desktop_app_surface.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/platform/linux_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delivers initial and forwarded Linux protocol URLs', () async {
    const channel = MethodChannel('flucord/protocol-test');
    const windowChannel = MethodChannel('window_manager');
    const notificationChannel = MethodChannel('local_notifier');
    const trayChannel = MethodChannel('tray_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      if (call.method == 'isMinimized' || call.method == 'isFocused') {
        return false;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      if (call.method == 'setup') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(trayChannel, (call) async => null);
    final integration = LinuxDesktopIntegration(
      initialArguments: const [
        '--ignored',
        'flucord://oauth/discord/callback?code=initial',
      ],
      channel: channel,
    );
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final workspace = WorkspaceController();
    final received = <Uri>[];
    final surface = FlucordAppSurface(
      chat: chat,
      workspace: workspace,
      visible: WindowVisible(),
      onProtocolUri: received.add,
    );
    addTearDown(chat.dispose);
    addTearDown(workspace.dispose);
    addTearDown(surface.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => messenger.setMockMethodCallHandler(windowChannel, null));
    addTearDown(
      () => messenger.setMockMethodCallHandler(notificationChannel, null),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(trayChannel, null));
    addTearDown(integration.dispose);

    await integration.initialize();
    expect(nativeCalls, hasLength(1));
    expect(nativeCalls.single.method, 'ready');
    expect(nativeCalls.single.arguments, isNull);
    integration.attach(surface);
    expect(received.single.queryParameters['code'], 'initial');

    final completer = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall(
          'url',
          'flucord://oauth/discord/callback?code=forwarded',
        ),
      ),
      (_) => completer.complete(),
    );
    await completer.future;

    expect(received.last.queryParameters['code'], 'forwarded');
  });
}