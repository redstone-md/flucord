import 'package:flutter/foundation.dart';
import 'package:protocol_handler/protocol_handler.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import 'desktop_integration.dart';
import 'desktop_protocol_router.dart';

final class MacosDesktopIntegration
    with ProtocolListener
    implements DesktopIntegration {
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();

  ChatController? _chatController;
  bool _protocolReady = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    try {
      await protocolHandler.register(ChannelLink.scheme);
      protocolHandler.addListener(this);
      _protocolReady = true;
      final initialUrl = await protocolHandler.getInitialUrl();
      if (initialUrl != null && initialUrl.isNotEmpty) {
        _protocolRouter.receive(initialUrl);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Flucord protocol handler unavailable: $error');
      }
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
  void onProtocolUrlReceived(String url) => _protocolRouter.receive(url);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chatController?.removeListener(_protocolRouter.flushChannelLink);
    if (_protocolReady) protocolHandler.removeListener(this);
    _protocolRouter.detach();
  }
}
