import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:window_manager/window_manager.dart';

import '../domain/channel_link.dart';
import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'desktop_protocol_router.dart';
import 'desktop_tray_coordinator.dart';

final class MacosDesktopIntegration
    with ProtocolListener, WindowListener
    implements DesktopIntegration {
  MacosDesktopIntegration() {
    _desktopTray = DesktopTrayCoordinator(showWindow: _showWindow, quit: _quit);
  }

  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();
  final DesktopMessageNotificationController _messageNotifications =
      DesktopMessageNotificationController(isFocused: windowManager.isFocused);
  late final DesktopTrayCoordinator _desktopTray;

  DesktopAppSurface? _surface;
  bool _windowReady = false;
  bool _protocolReady = false;
  bool _allowClose = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    await _initializeWindow();
    await _messageNotifications.initialize();
    await _initializeProtocol();
    await _initializeTray();
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
      _debugFailure('protocol handler', error);
    }
  }

  Future<void> _initializeTray() async {
    await _desktopTray.initialize();
    if (_windowReady && _desktopTray.isReady) {
      await windowManager.setPreventClose(true);
    }
  }

  @override
  void attach(DesktopAppSurface surface) {
    _protocolRouter.attach(surface);
    _messageNotifications.attach(surface: surface, showWindow: _showWindow);
    _desktopTray.attach(surface);
  }

  @override
  void onProtocolUrlReceived(String url) {
    unawaited(_showWindow());
    _protocolRouter.receive(url);
  }

  Future<void> _showWindow() async {
    if (!_windowReady) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    _surface?.setApplicationActive(true);
  }

  @override
  void onWindowFocus() => _surface?.setApplicationActive(true);

  @override
  void onWindowBlur() => _surface?.setApplicationActive(false);

  @override
  void onWindowClose() {
    if (!_allowClose && _desktopTray.isReady) {
      _surface?.setApplicationActive(false);
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

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _protocolRouter.detach();
    await _messageNotifications.dispose();
    await _desktopTray.dispose();
    if (_protocolReady) protocolHandler.removeListener(this);
    if (_windowReady) windowManager.removeListener(this);
  }
}
