import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'desktop_protocol_router.dart';
import 'desktop_tray_coordinator.dart';

final class LinuxDesktopIntegration
    with WindowListener
    implements DesktopIntegration {
  factory LinuxDesktopIntegration({
    required List<String> initialArguments,
    MethodChannel channel = const MethodChannel('flucord/protocol'),
  }) => LinuxDesktopIntegration._(List.unmodifiable(initialArguments), channel);

  LinuxDesktopIntegration._(this._initialArguments, this._channel) {
    _desktopTray = DesktopTrayCoordinator(showWindow: _showWindow, quit: _quit);
  }

  final List<String> _initialArguments;
  final MethodChannel _channel;
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();
  final DesktopMessageNotificationController _messageNotifications =
      DesktopMessageNotificationController(isFocused: windowManager.isFocused);
  late final DesktopTrayCoordinator _desktopTray;

  ChatController? _chatController;
  bool _windowReady = false;
  bool _allowClose = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    await _initializeWindow();
    await _messageNotifications.initialize();
    await _initializeTray();
    _channel.setMethodCallHandler(_handleMethodCall);
    await _channel.invokeMethod<void>('ready');
    for (final argument in _initialArguments) {
      _protocolRouter.receive(argument);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final url = call.arguments;
    if (call.method == 'url' && url is String) {
      unawaited(_showWindow());
      _protocolRouter.receive(url);
    }
  }

  Future<void> _initializeWindow() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      _windowReady = true;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Flucord window manager unavailable: $error');
      }
    }
  }

  Future<void> _initializeTray() async {
    await _desktopTray.initialize();
    if (_windowReady && _desktopTray.isReady) {
      await windowManager.setPreventClose(true);
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
    _desktopTray.attach(chatController);
    chatController.addListener(_protocolRouter.flushChannelLink);
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

  @override
  void onWindowClose() {
    if (!_allowClose && _desktopTray.isReady) {
      _chatController?.setApplicationActive(false);
      unawaited(windowManager.hide());
    }
  }

  Future<void> _quit() async {
    _allowClose = true;
    if (_windowReady) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chatController?.removeListener(_protocolRouter.flushChannelLink);
    await _messageNotifications.dispose();
    await _desktopTray.dispose();
    _channel.setMethodCallHandler(null);
    if (_windowReady) windowManager.removeListener(this);
    _protocolRouter.detach();
  }
}
