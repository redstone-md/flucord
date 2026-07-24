import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/system_message_text.dart';
import '../application/workspace_controller.dart';
import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import 'desktop_integration.dart';

final class WindowsDesktopIntegration
    with WindowListener, TrayListener, ProtocolListener
    implements DesktopIntegration {
  static const _updateFeedUrl = String.fromEnvironment(
    'FLUCORD_UPDATE_FEED_URL',
  );

  ChatController? _chatController;
  WorkspaceController? _workspaceController;
  StreamSubscription<MessageUpsertedEvent>? _messageSubscription;
  ChannelLink? _pendingLink;
  Uri? _pendingProtocolUri;
  void Function(Uri uri)? _protocolUriHandler;
  bool _windowReady = false;
  bool _notifierReady = false;
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
    _workspaceController = workspaceController;
    _protocolUriHandler = onProtocolUri;
    chatController.addListener(_handleChatChanged);
    _messageSubscription = chatController.incomingMessages.listen(
      (event) => unawaited(_showMessageNotification(event)),
    );
    final pendingProtocolUri = _pendingProtocolUri;
    if (pendingProtocolUri != null) {
      _pendingProtocolUri = null;
      onProtocolUri(pendingProtocolUri);
    }
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
    try {
      await localNotifier.setup(
        appName: 'Flucord',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _notifierReady = true;
    } catch (error) {
      _debugFailure('notifications', error);
    }
  }

  Future<void> _initializeProtocol() async {
    try {
      await protocolHandler.register(ChannelLink.scheme);
      protocolHandler.addListener(this);
      _protocolReady = true;
      final initialUrl = await protocolHandler.getInitialUrl();
      if (initialUrl != null && initialUrl.isNotEmpty) {
        _receiveProtocolUrl(initialUrl);
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
    _openPendingLink();
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

  Future<void> _showMessageNotification(MessageUpsertedEvent event) async {
    final chatController = _chatController;
    final workspace = chatController?.workspace;
    if (!_notifierReady || chatController == null || workspace == null) return;

    if (_windowReady &&
        chatController.activeChannelId == event.message.channelId &&
        await windowManager.isFocused()) {
      return;
    }

    final channel = _channelOrNull(workspace, event.message.channelId);
    if (channel == null) return;
    final space = _spaceOrNull(workspace, channel.spaceId);
    final author = workspace.memberOrNull(event.message.authorId);
    final link = ChannelLink(spaceId: channel.spaceId, channelId: channel.id);
    final notification = LocalNotification(
      identifier: 'flucord-${event.message.id}',
      title: '${author?.displayName ?? 'New message'} - #${channel.name}',
      subtitle: space?.name,
      body: _notificationBody(event.message, author?.displayName),
    );
    notification.onClick = () => unawaited(_activateLink(link));
    try {
      await notification.show();
    } catch (error) {
      _debugFailure('notification delivery', error);
    }
  }

  String _notificationBody(ChatMessage message, String? authorName) {
    var body = message.isSystem
        ? SystemMessageText.describe(message, authorName ?? 'Someone')
        : message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty) {
      final question = message.poll?.question.trim();
      if (question != null && question.isNotEmpty) return question;
      if (message.stickers.isNotEmpty) return message.stickers.first.name;
      final count = message.attachments.length;
      body = count == 1
          ? 'Attachment: ${message.attachments.first.fileName}'
          : count > 1
          ? '$count attachments'
          : message.embeds.isNotEmpty
          ? 'Embedded content'
          : 'New message';
    }
    return body.length <= 180 ? body : '${body.substring(0, 177)}...';
  }

  ConversationChannel? _channelOrNull(
    ChatWorkspace workspace,
    String channelId,
  ) {
    for (final channel in workspace.channels) {
      if (channel.id == channelId) return channel;
    }
    return null;
  }

  CommunitySpace? _spaceOrNull(ChatWorkspace workspace, String spaceId) {
    for (final space in workspace.spaces) {
      if (space.id == spaceId) return space;
    }
    return null;
  }

  Future<void> _activateLink(ChannelLink link) async {
    _pendingLink = link;
    await _showWindow();
    _openPendingLink();
  }

  void _openPendingLink() {
    final link = _pendingLink;
    final chatController = _chatController;
    final workspaceController = _workspaceController;
    final workspace = chatController?.workspace;
    if (link == null ||
        chatController == null ||
        workspaceController == null ||
        workspace == null) {
      return;
    }
    if (!workspaceController.openChannelLink(workspace, link)) {
      _pendingLink = null;
      return;
    }
    _pendingLink = null;
    unawaited(chatController.openChannel(link.channelId));
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
    final link = ChannelLink.tryParse(url);
    if (link != null) {
      unawaited(_activateLink(link));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != ChannelLink.scheme) return;
    unawaited(_showWindow());
    final handler = _protocolUriHandler;
    if (handler == null) {
      _pendingProtocolUri = uri;
    } else {
      handler(uri);
    }
  }

  void _receiveProtocolUrl(String url) {
    final link = ChannelLink.tryParse(url);
    if (link != null) {
      _pendingLink = link;
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != ChannelLink.scheme) return;
    final handler = _protocolUriHandler;
    if (handler == null) {
      _pendingProtocolUri = uri;
    } else {
      handler(uri);
    }
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
    _protocolUriHandler = null;
    await _messageSubscription?.cancel();
    if (_protocolReady) protocolHandler.removeListener(this);
    if (_trayReady) {
      trayManager.removeListener(this);
      await trayManager.destroy();
    }
    if (_windowReady) windowManager.removeListener(this);
  }
}
