import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/system_message_text.dart';
import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

typedef DesktopFocusProbe = Future<bool> Function();
typedef ChannelLinkActivator = Future<void> Function(ChannelLink link);

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

final class DesktopMessageNotificationController {
  factory DesktopMessageNotificationController({
    required DesktopFocusProbe isFocused,
    DesktopNotificationGateway? gateway,
  }) => DesktopMessageNotificationController._(
    isFocused,
    gateway ?? LocalDesktopNotificationGateway(),
  );

  DesktopMessageNotificationController._(this._isFocused, this._gateway);

  final DesktopFocusProbe _isFocused;
  final DesktopNotificationGateway _gateway;

  ChatController? _chatController;
  ChannelLinkActivator? _activateLink;
  StreamSubscription<MessageUpsertedEvent>? _subscription;
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
    required ChatController chatController,
    required ChannelLinkActivator onActivateLink,
  }) {
    if (_disposed) return;
    _chatController = chatController;
    _activateLink = onActivateLink;
    unawaited(_subscription?.cancel());
    _subscription = chatController.incomingMessages.listen(
      (event) => unawaited(notify(event)),
    );
  }

  Future<void> notify(MessageUpsertedEvent event) async {
    final chatController = _chatController;
    final workspace = chatController?.workspace;
    final activateLink = _activateLink;
    if (!_ready ||
        _disposed ||
        !event.isNew ||
        chatController == null ||
        workspace == null ||
        activateLink == null ||
        event.message.authorId == workspace.currentMemberId) {
      return;
    }

    if (chatController.activeChannelId == event.message.channelId &&
        await _isFocusedSafely()) {
      return;
    }

    final channel = workspace.channelOrNull(event.message.channelId);
    if (channel == null) return;
    final space = workspace.spaceById(channel.spaceId);
    final author =
        event.member ?? workspace.memberOrNull(event.message.authorId);
    final link = ChannelLink(spaceId: channel.spaceId, channelId: channel.id);
    final request = DesktopNotificationRequest(
      identifier: 'flucord-${event.message.id}',
      title: '${author?.displayName ?? 'New message'} - #${channel.name}',
      subtitle: space.name,
      body: _notificationBody(event.message, author?.displayName),
      onClick: () => activateLink(link),
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

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _chatController = null;
    _activateLink = null;
    await _subscription?.cancel();
    await _gateway.dispose();
  }
}
