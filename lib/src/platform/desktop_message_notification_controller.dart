import 'dart:async';

import 'package:local_notifier/local_notifier.dart';

import 'desktop_integration.dart';
import '../app_log.dart';

typedef DesktopFocusProbe = Future<bool> Function();

final class DesktopNotificationRequest {
  const DesktopNotificationRequest({
    required this.identifier,
    required this.title,
    required this.body,
    required this.onClick,
    this.subtitle,
  });

  final String identifier;
  final String title;
  final String? subtitle;
  final String body;
  final Future<void> Function() onClick;
}

abstract interface class DesktopNotificationGateway {
  Future<void> initialize();

  Future<void> show(DesktopNotificationRequest request);

  Future<void> dispose();
}

final class LocalDesktopNotificationGateway
    implements DesktopNotificationGateway {
  LocalDesktopNotificationGateway();

  final Set<LocalNotification> _notifications = {};

  @override
  Future<void> initialize() => localNotifier.setup(
    appName: 'Flucord',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    late final LocalNotification notification;
    notification = LocalNotification(
      identifier: request.identifier,
      title: request.title,
      subtitle: request.subtitle,
      body: request.body,
    );
    notification.onClose = (_) => unawaited(_destroy(notification));
    notification.onClick = () => unawaited(
      Future<void>(() async {
        try {
          await request.onClick();
        } finally {
          await _destroy(notification);
        }
      }),
    );
    _notifications.add(notification);
    try {
      await notification.show();
    } catch (_) {
      await _destroy(notification);
      rethrow;
    }
  }

  Future<void> _destroy(LocalNotification notification) async {
    if (!_notifications.remove(notification)) return;
    try {
      await notification.destroy();
    } on Object {
      // The native notification may already have been removed by the OS.
    }
  }

  @override
  Future<void> dispose() async {
    for (final notification in _notifications.toList(growable: false)) {
      await _destroy(notification);
    }
  }
}

/// Shows the app's message notifications as native toasts.
///
/// The app side has already decided a message should interrupt and formatted
/// it; this side owns the window facts. A toast is dropped when streamer mode
/// is on, and when it would land on the channel the user is looking at in a
/// focused window.
final class DesktopMessageNotificationController {
  factory DesktopMessageNotificationController({
    required DesktopFocusProbe isFocused,
    DesktopNotificationGateway? gateway,
    bool Function()? isSuppressed,
  }) => DesktopMessageNotificationController._(
    isFocused,
    gateway ?? LocalDesktopNotificationGateway(),
    isSuppressed ?? _neverSuppressed,
  );

  DesktopMessageNotificationController._(
    this._isFocused,
    this._gateway,
    this._isSuppressed,
  );

  static bool _neverSuppressed() => false;

  final DesktopFocusProbe _isFocused;
  final DesktopNotificationGateway _gateway;

  /// Whether something outside the account — streamer mode — is holding
  /// notifications back.
  final bool Function() _isSuppressed;

  DesktopAppSurface? _surface;
  Future<void> Function()? _showWindow;
  StreamSubscription<DesktopMessageNotification>? _subscription;
  bool _ready = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed) return;
    try {
      await _gateway.initialize();
      _ready = true;
    } on Object catch (error) {
      _debugFailure('notifications', error);
    }
  }

  void attach({
    required DesktopAppSurface surface,
    required Future<void> Function() showWindow,
  }) {
    if (_disposed) return;
    _surface = surface;
    _showWindow = showWindow;
    unawaited(_subscription?.cancel());
    _subscription = surface.messageNotifications.listen(
      (notification) => unawaited(notify(notification)),
    );
  }

  Future<void> notify(DesktopMessageNotification notification) async {
    final surface = _surface;
    final showWindow = _showWindow;
    if (!_ready || _disposed || surface == null || showWindow == null) {
      return;
    }

    // Read per message: streamer mode can go on between one message and the
    // next, and a toast is exactly what it exists to keep off a stream.
    if (_isSuppressed()) return;

    if (surface.activeChannelId == notification.link.channelId &&
        await _isFocusedSafely()) {
      return;
    }

    final link = notification.link;
    final request = DesktopNotificationRequest(
      identifier: notification.identifier,
      title: notification.title,
      subtitle: notification.subtitle,
      body: notification.body,
      onClick: () async {
        await showWindow();
        surface.openChannelLink(link);
      },
    );
    try {
      await _gateway.show(request);
    } on Object catch (error) {
      _debugFailure('notification delivery', error);
    }
  }

  Future<bool> _isFocusedSafely() async {
    try {
      return await _isFocused();
    } on Object catch (error) {
      _debugFailure('window focus', error);
      return false;
    }
  }

  void _debugFailure(String feature, Object error) {
    AppLog.warning('desktop', '$feature unavailable', error: error);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _surface = null;
    _showWindow = null;
    await _subscription?.cancel();
    await _gateway.dispose();
  }
}
