import 'package:flutter/services.dart';

import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import 'desktop_integration.dart';
import 'desktop_protocol_router.dart';

final class LinuxDesktopIntegration implements DesktopIntegration {
  factory LinuxDesktopIntegration({
    required List<String> initialArguments,
    MethodChannel channel = const MethodChannel('flucord/protocol'),
  }) => LinuxDesktopIntegration._(List.unmodifiable(initialArguments), channel);

  LinuxDesktopIntegration._(this._initialArguments, this._channel);

  final List<String> _initialArguments;
  final MethodChannel _channel;
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();

  ChatController? _chatController;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    await _channel.invokeMethod<void>('ready');
    for (final argument in _initialArguments) {
      _protocolRouter.receive(argument);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final url = call.arguments;
    if (call.method == 'url' && url is String) {
      _protocolRouter.receive(url);
    }
  }

  @override
  void attach({
    required ChatController chatController,
    required WorkspaceController workspaceController,
    required void Function(Uri uri) onProtocolUri,
  }) {
    _chatController = chatController;
    _protocolRouter.attach(
      chatController: chatController,
      workspaceController: workspaceController,
      onProtocolUri: onProtocolUri,
    );
    chatController.addListener(_protocolRouter.flushChannelLink);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chatController?.removeListener(_protocolRouter.flushChannelLink);
    _channel.setMethodCallHandler(null);
    _protocolRouter.detach();
  }
}
