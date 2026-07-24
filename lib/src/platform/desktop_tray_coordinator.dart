import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../application/chat_controller.dart';

enum DesktopTrayAction { open, checkUpdates, quit }

typedef DesktopTrayActionHandler =
    Future<void> Function(DesktopTrayAction action);

final class DesktopTrayConfiguration {
  const DesktopTrayConfiguration({
    this.includeUpdateAction = false,
    this.updateActionEnabled = false,
  });

  final bool includeUpdateAction;
  final bool updateActionEnabled;
}

abstract interface class DesktopTrayGateway {
  Future<void> initialize({
    required DesktopTrayConfiguration configuration,
    required DesktopTrayActionHandler onAction,
  });

  Future<void> setUnreadCount(int count);

  Future<void> dispose();
}

final class NativeDesktopTrayGateway
    with TrayListener
    implements DesktopTrayGateway {
  static const _windowsIconAsset = 'windows/runner/resources/app_icon.ico';
  static const _portableIconAsset =
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png';

  DesktopTrayConfiguration _configuration = const DesktopTrayConfiguration();
  DesktopTrayActionHandler? _onAction;
  bool _iconCreated = false;
  bool _listenerAttached = false;

  @override
  Future<void> initialize({
    required DesktopTrayConfiguration configuration,
    required DesktopTrayActionHandler onAction,
  }) async {
    _configuration = configuration;
    _onAction = onAction;
    final iconPath = await _materializeIcon();
    await trayManager.setIcon(iconPath);
    _iconCreated = true;
    trayManager.addListener(this);
    _listenerAttached = true;
    await setUnreadCount(0);
  }

  Future<String> _materializeIcon() async {
    final isWindows = Platform.isWindows;
    final asset = isWindows ? _windowsIconAsset : _portableIconAsset;
    final data = await rootBundle.load(asset);
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}flucord',
    );
    await directory.create(recursive: true);
    final extension = isWindows ? 'ico' : 'png';
    final file = File(
      '${directory.path}${Platform.pathSeparator}tray-icon.$extension',
    );
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  @override
  Future<void> setUnreadCount(int count) async {
    if (!_iconCreated) return;
    final unreadLabel = count == 0
        ? 'Open Flucord'
        : 'Open Flucord ($count unread)';
    final items = <MenuItem>[MenuItem(key: 'open', label: unreadLabel)];
    if (_configuration.includeUpdateAction) {
      items.add(
        MenuItem(
          key: 'check_updates',
          label: 'Check for updates',
          disabled: !_configuration.updateActionEnabled,
        ),
      );
    }
    items
      ..add(MenuItem.separator())
      ..add(MenuItem(key: 'quit', label: 'Quit Flucord'));
    await trayManager.setContextMenu(Menu(items: items));
    if (!Platform.isLinux) {
      final tooltip = count == 0 ? 'Flucord' : 'Flucord - $count unread';
      await trayManager.setToolTip(tooltip);
    }
  }

  @override
  void onTrayIconMouseDown() => _dispatch(DesktopTrayAction.open);

  @override
  void onTrayIconRightMouseDown() {
    if (!Platform.isLinux) unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        _dispatch(DesktopTrayAction.open);
      case 'check_updates':
        _dispatch(DesktopTrayAction.checkUpdates);
      case 'quit':
        _dispatch(DesktopTrayAction.quit);
    }
  }

  void _dispatch(DesktopTrayAction action) {
    final onAction = _onAction;
    if (onAction != null) unawaited(onAction(action));
  }

  @override
  Future<void> dispose() async {
    _onAction = null;
    if (_listenerAttached) {
      trayManager.removeListener(this);
      _listenerAttached = false;
    }
    if (_iconCreated) {
      _iconCreated = false;
      await trayManager.destroy();
    }
  }
}

final class DesktopTrayCoordinator {
  factory DesktopTrayCoordinator({
    required Future<void> Function() showWindow,
    required Future<void> Function() quit,
    Future<void> Function()? checkForUpdates,
    DesktopTrayConfiguration configuration = const DesktopTrayConfiguration(),
    DesktopTrayGateway? gateway,
  }) => DesktopTrayCoordinator._(
    showWindow,
    quit,
    checkForUpdates,
    configuration,
    gateway ?? NativeDesktopTrayGateway(),
  );

  DesktopTrayCoordinator._(
    this._showWindow,
    this._quit,
    this._checkForUpdates,
    this._configuration,
    this._gateway,
  );

  final Future<void> Function() _showWindow;
  final Future<void> Function() _quit;
  final Future<void> Function()? _checkForUpdates;
  final DesktopTrayConfiguration _configuration;
  final DesktopTrayGateway _gateway;

  ChatController? _chatController;
  bool _ready = false;
  bool _disposed = false;
  int? _lastUnreadCount;

  bool get isReady => _ready && !_disposed;

  Future<void> initialize() async {
    if (_disposed) return;
    try {
      await _gateway.initialize(
        configuration: _configuration,
        onAction: _handleAction,
      );
      _ready = true;
      _syncUnreadCount();
    } on Object catch (error) {
      _debugFailure('tray', error);
      await _disposeGatewaySafely();
    }
  }

  void attach(ChatController chatController) {
    if (_disposed) return;
    _chatController?.removeListener(_syncUnreadCount);
    _chatController = chatController;
    chatController.addListener(_syncUnreadCount);
    _syncUnreadCount();
  }

  void _syncUnreadCount() {
    final workspace = _chatController?.workspace;
    if (!isReady || workspace == null) return;
    final unreadCount = workspace.channels.where((item) => item.unread).length;
    if (_lastUnreadCount == unreadCount) return;
    _lastUnreadCount = unreadCount;
    unawaited(_setUnreadCount(unreadCount));
  }

  Future<void> _setUnreadCount(int count) async {
    try {
      await _gateway.setUnreadCount(count);
    } on Object catch (error) {
      _debugFailure('tray update', error);
    }
  }

  Future<void> _handleAction(DesktopTrayAction action) async {
    if (_disposed) return;
    try {
      switch (action) {
        case DesktopTrayAction.open:
          await _showWindow();
        case DesktopTrayAction.checkUpdates:
          if (_configuration.updateActionEnabled) {
            await _checkForUpdates?.call();
          }
        case DesktopTrayAction.quit:
          await dispose();
          await _quit();
      }
    } on Object catch (error) {
      _debugFailure('tray action', error);
    }
  }

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _chatController?.removeListener(_syncUnreadCount);
    _chatController = null;
    await _disposeGatewaySafely();
  }

  Future<void> _disposeGatewaySafely() async {
    try {
      await _gateway.dispose();
    } on Object catch (error) {
      _debugFailure('tray disposal', error);
    }
  }
}
