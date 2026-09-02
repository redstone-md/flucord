import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../platform/desktop_integration.dart';
import '../domain/channel_link.dart';
import 'chat_controller.dart';
import 'system_message_text.dart';
import 'window_visible.dart';
import 'workspace_controller.dart';

/// The application side of the desktop seam ([DesktopAppSurface]): the chat,
/// workspace, and protocol surfaces of the running app presented as the state
/// desktop chrome reads and the actions it triggers.
///
/// Constructed with the app's controllers and handed to the platform layer at
/// attach time; no platform file reads a controller.
final class FlucordAppSurface extends ChangeNotifier
    implements DesktopAppSurface {
  FlucordAppSurface({
    required ChatController chat,
    required WorkspaceController workspace,
    required WindowVisible visible,
    required void Function(Uri uri) onProtocolUri,
    Stream<MessageUpsertedEvent>? incomingMessages,
  }) : _chat = chat,
       _workspace = workspace,
       _visible = visible,
       _onProtocolUri = onProtocolUri {
    _chat.addListener(_chatChanged);
    _messages = incomingMessages ?? chat.incomingMessages;
    _messageSubscription = _messages.listen(
      (event) => unawaited(_notify(event)),
    );
  }

  final ChatController _chat;
  final WorkspaceController _workspace;
  final WindowVisible _visible;
  final void Function(Uri uri) _onProtocolUri;
  late final Stream<MessageUpsertedEvent> _messages;
  late final StreamSubscription<MessageUpsertedEvent> _messageSubscription;

  final StreamController<DesktopMessageNotification> _notifications =
      StreamController.broadcast();

  ChannelLink? _pendingChannelLink;
  bool _disposed = false;

  @override
  int? get unreadChannelCount =>
      _chat.workspace?.channels.where((channel) => channel.unread).length;

  @override
  String? get activeChannelId => _chat.activeChannelId;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      _notifications.stream;

  @override
  void openChannelLink(ChannelLink link) {
    if (_disposed) return;
    final workspace = _chat.workspace;
    if (workspace == null) {
      // The link is held until the workspace loads; a newer link replaces it,
      // because it is the user's latest intent that counts.
      _pendingChannelLink = link;
      return;
    }
    if (!_workspace.openChannelLink(workspace, link)) return;
    unawaited(_chat.openChannel(link.channelId));
  }

  @override
  void handleProtocolUri(Uri uri) => _onProtocolUri(uri);

  /// Marks the app active or inactive: whether the room is being looked at
  /// decides what the chat reads, and whether the sender's own preview is
  /// worth decoding. Focus is the platform fact behind it.
  @override
  void setApplicationActive(bool value) {
    _chat.setApplicationActive(value);
    _visible.setFocused(value);
  }

  /// Tells whether anything of the window is on screen, which watched
  /// sessions read to suspend (ADR-0003). A window that only lost the focus
  /// is still on screen, and still watched.
  @override
  void setWindowVisible(bool value) {
    _visible.setInView(value);
  }

  /// Re-checks whatever the desktop holds on the app's behalf, and tells the
  /// chrome (the tray, pending protocol links) that app state moved.
  void _chatChanged() {
    final link = _pendingChannelLink;
    if (link != null && _chat.workspace != null) {
      _pendingChannelLink = null;
      openChannelLink(link);
    }
    notifyListeners();
  }

  Future<void> _notify(MessageUpsertedEvent event) async {
    if (_disposed || !event.isNew) return;
    final workspace = _chat.workspace;
    if (workspace == null) return;
    if (event.message.authorId == workspace.currentMemberId) return;

    // Quiet mode is account state that another device can turn on mid-session,
    // so it is read per message rather than captured when this surface was
    // constructed.
    if (_chat.suppressesMessageNotifications) return;

    final channel = workspace.channelOrNull(event.message.channelId);
    if (channel == null) return;

    // R04's notification settings are the account's own answer to "should this
    // have interrupted me": a muted channel or guild, a channel set to mentions
    // only, or `suppress_everyone` on a broadcast all stop here. They are read
    // per message rather than captured once, because another device can
    // change them mid-session exactly as it can change quiet mode.
    if (!_chat.readState.allowsDesktopNotification(
      channel,
      mentionsCurrentMember:
          event.mentionsCurrentMember || event.message.mentionsCurrentMember,
      mentionsEveryone: event.message.mentionsEveryone,
    )) {
      return;
    }

    final space = workspace.spaceById(channel.spaceId);
    final author =
        event.member ?? workspace.memberOrNull(event.message.authorId);
    _notifications.add(
      DesktopMessageNotification(
        identifier: 'flucord-${event.message.id}',
        title: '${author?.displayName ?? 'New message'} - #${channel.name}',
        subtitle: space.name,
        body: _notificationBody(event.message, author?.displayName),
        link: ChannelLink(spaceId: channel.spaceId, channelId: channel.id),
      ),
    );
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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chat.removeListener(_chatChanged);
    await _messageSubscription.cancel();
    await _notifications.close();
    super.dispose();
  }
}
