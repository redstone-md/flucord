import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:window_manager/window_manager.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'desktop_protocol_router.dart';

final class MacosDesktopIntegration
    with ProtocolListener, WindowListener
    implements DesktopIntegration {
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();
  final DesktopMessageNotificationController _messageNotifications =
      DesktopMessageNotificationController(isFocused: windowManager.isFocused);

  ChatController? _chatController;
  bool _windowReady = false;
  bool _protocolReady = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    await _initializeWindow();
    await _messageNotifications.initialize();
    await _initializeProtocol();
  }

  Future<void> _initializeWindow() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      _windowReady = true;
    } on Object catch (error) {
      _debugFailure('window manager', error);
    }
  }

  Future<void> _initializeProtocol() async {
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
    _messageNotifications.attach(
      chatController: chatController,
      onActivateLink: _activateLink,
    );
    chatController.addListener(_protocolRouter.flushChannelLink);
  }

  @override
  void onProtocolUrlReceived(String url) {
    unawaited(_showWindow());
    _protocolRouter.receive(url);
  }

  Future<void> _activateLink(ChannelLink link) async {
    await _showWindow();
    _protocolRouter.receive(link.toUri().toString());
  }

  Future<void> _showWindow() async {
    if (!_windowReady) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    _chatController?.setApplicationActive(true);
  }

  @override
  void onWindowFocus() => _chatController?.setApplicationActive(true);

  @override
  void onWindowBlur() => _chatController?.setApplicationActive(false);

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chatController?.removeListener(_protocolRouter.flushChannelLink);
    await _messageNotifications.dispose();
    if (_protocolReady) protocolHandler.removeListener(this);
    if (_windowReady) windowManager.removeListener(this);
    _protocolRouter.detach();
  }
}
