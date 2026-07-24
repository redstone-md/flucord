import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'desktop_protocol_router.dart';

final class WindowsDesktopIntegration
    with WindowListener, TrayListener, ProtocolListener
    implements DesktopIntegration {
  static const _updateFeedUrl = String.fromEnvironment(
    'FLUCORD_UPDATE_FEED_URL',
  );

  ChatController? _chatController;
  final DesktopProtocolRouter _protocolRouter = DesktopProtocolRouter();
  final DesktopMessageNotificationController _messageNotifications =
      DesktopMessageNotificationController(isFocused: windowManager.isFocused);
  bool _windowReady = false;
  bool _trayReady = false;
  bool _protocolReady = false;
  bool _updaterReady = false;
  bool _allowClose = false;
  bool _disposed = false;
  int? _lastUnreadCount;

  @override
  Future<void> initialize() async {
    await _initializeWindow();
    await _initializeNotifications();
    await _initializeProtocol();
    await _initializeTray();
    await _initializeUpdater();
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
    chatController.addListener(_handleChatChanged);
    _handleChatChanged();
  }

  Future<void> _initializeWindow() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      _windowReady = true;
    } catch (error) {
      _debugFailure('window manager', error);
    }
  }

  Future<void> _initializeNotifications() async {
    await _messageNotifications.initialize();
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
    } catch (error) {
      _debugFailure('protocol handler', error);
    }
  }

  Future<void> _initializeTray() async {
    try {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      final iconPath =
          '$executableDirectory${Platform.pathSeparator}data'
          '${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}'
          'windows${Platform.pathSeparator}runner${Platform.pathSeparator}'
          'resources${Platform.pathSeparator}app_icon.ico';
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Flucord');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: 'Open Flucord'),
            MenuItem(
              key: 'check_updates',
              label: 'Check for updates',
              disabled: !_hasValidFeedUrl,
            ),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: 'Quit Flucord'),
          ],
        ),
      );
      trayManager.addListener(this);
      _trayReady = true;
    } catch (error) {
      _debugFailure('tray', error);
    }
  }

  Future<void> _initializeUpdater() async {
    if (!_hasValidFeedUrl) return;
    try {
      await autoUpdater.setFeedURL(_updateFeedUrl.trim());
      await autoUpdater.setScheduledCheckInterval(86400);
      _updaterReady = true;
    } catch (error) {
      _debugFailure('auto updater', error);
    }
  }

  bool get _hasValidFeedUrl {
    final uri = Uri.tryParse(_updateFeedUrl.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  void _handleChatChanged() {
    _protocolRouter.flushChannelLink();
    final workspace = _chatController?.workspace;
    if (!_trayReady || workspace == null) return;
    final unreadCount = workspace.channels.where((item) => item.unread).length;
    if (_lastUnreadCount == unreadCount) return;
    _lastUnreadCount = unreadCount;
    final tooltip = unreadCount == 0
        ? 'Flucord'
        : 'Flucord - $unreadCount unread';
    unawaited(trayManager.setToolTip(tooltip));
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
  void onProtocolUrlReceived(String url) {
    unawaited(_showWindow());
    _protocolRouter.receive(url);
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindow());
      case 'check_updates':
        if (_updaterReady) unawaited(autoUpdater.checkForUpdates());
      case 'exit_app':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    if (!_allowClose) {
      _chatController?.setApplicationActive(false);
      unawaited(windowManager.hide());
    }
  }

  @override
  void onWindowFocus() => _chatController?.setApplicationActive(true);

  @override
  void onWindowBlur() => _chatController?.setApplicationActive(false);

  Future<void> _quit() async {
    _allowClose = true;
    await windowManager.setPreventClose(false);
    if (_trayReady) await trayManager.destroy();
    await windowManager.close();
  }

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chatController?.removeListener(_handleChatChanged);
    _protocolRouter.detach();
    await _messageNotifications.dispose();
    if (_protocolReady) protocolHandler.removeListener(this);
    if (_trayReady) {
      trayManager.removeListener(this);
      await trayManager.destroy();
    }
    if (_windowReady) windowManager.removeListener(this);
  }
}
