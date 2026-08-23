import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'desktop_protocol_intake.dart';
import 'desktop_protocol_router.dart';
import 'desktop_tray_coordinator.dart';

/// The app's update channel, when the platform has one. Windows wraps
/// auto_updater, which reads an appcast: an XML feed listing releases. The
/// other platforms ship none.
abstract interface class DesktopUpdater {
  /// Registers the update feed with the OS, when one was configured.
  Future<void> initialize();

  /// Starts a check outside the updater's own schedule.
  Future<void> checkForUpdates();
}

/// The desktop attach and teardown flow every platform shares: window
/// lifecycle, message notifications, tray, and protocol routing.
///
/// A platform shell configures this flow with what differs there: how
/// flucord:// URLs arrive, the tray details, and the updater. Closing the
/// window hides to tray once the tray exists; quitting closes for real.
final class DesktopIntegrationFlow
    with WindowListener
    implements DesktopIntegration {
  DesktopIntegrationFlow({
    required DesktopProtocolIntake protocolIntake,
    DesktopTrayConfiguration trayConfiguration =
        const DesktopTrayConfiguration(),
    DesktopUpdater? updater,
  }) : _protocolIntake = protocolIntake,
       _updater = updater {
    _desktopTray = DesktopTrayCoordinator(
      showWindow: _showWindow,
      quit: _quit,
      checkForUpdates: updater?.checkForUpdates,
      configuration: trayConfiguration,
    );
  }

  final DesktopProtocolIntake _protocolIntake;
  final DesktopUpdater? _updater;
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();
  final DesktopMessageNotificationController _messageNotifications =
      DesktopMessageNotificationController(isFocused: windowManager.isFocused);
  late final DesktopTrayCoordinator _desktopTray;

  DesktopAppSurface? _surface;
  bool _windowReady = false;
  bool _allowClose = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    await _initializeWindow();
    await _messageNotifications.initialize();
    await _initializeProtocol();
    await _initializeTray();
    await _updater?.initialize();
  }

  @override
  void attach(DesktopAppSurface surface) {
    _surface = surface;
    _protocolRouter.attach(surface);
    _messageNotifications.attach(surface: surface, showWindow: _showWindow);
    _desktopTray.attach(surface);
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
    final launchUrls = await _protocolIntake.start(_receiveProtocolUrl);
    for (final url in launchUrls) {
      _protocolRouter.receive(url);
    }
  }

  /// A URL that arrives while the app runs means the OS raised the app for
  /// it, so the window comes up with it. A launch URL only routes: the app
  /// was starting anyway.
  void _receiveProtocolUrl(String url) {
    unawaited(_showWindow());
    _protocolRouter.receive(url);
  }

  Future<void> _initializeTray() async {
    await _desktopTray.initialize();
    if (_windowReady && _desktopTray.isReady) {
      await windowManager.setPreventClose(true);
    }
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
    _protocolIntake.dispose();
    if (_windowReady) windowManager.removeListener(this);
  }
}
