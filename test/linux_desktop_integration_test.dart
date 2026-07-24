import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/platform/linux_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delivers initial and forwarded Linux protocol URLs', () async {
    const channel = MethodChannel('flucord/protocol-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return null;
    });
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
    addTearDown(chat.dispose);
    addTearDown(workspace.dispose);
    addTearDown(integration.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await integration.initialize();
    expect(nativeCalls, hasLength(1));
    expect(nativeCalls.single.method, 'ready');
    expect(nativeCalls.single.arguments, isNull);
    integration.attach(
      chatController: chat,
      workspaceController: workspace,
      onProtocolUri: received.add,
    );
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
