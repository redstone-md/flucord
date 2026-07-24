import 'dart:async';

import '../application/channel_link.dart';
import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';

final class DesktopProtocolRouter {
  ChatController? _chatController;
  WorkspaceController? _workspaceController;
  void Function(Uri uri)? _onProtocolUri;
  ChannelLink? _pendingChannelLink;
  Uri? _pendingProtocolUri;

  void attach({
    required ChatController chatController,
    required WorkspaceController workspaceController,
    required void Function(Uri uri) onProtocolUri,
  }) {
    _chatController = chatController;
    _workspaceController = workspaceController;
    _onProtocolUri = onProtocolUri;
    final pendingProtocolUri = _pendingProtocolUri;
    if (pendingProtocolUri != null) {
      _pendingProtocolUri = null;
      onProtocolUri(pendingProtocolUri);
    }
    flushChannelLink();
  }

  void receive(String rawUrl) {
    final channelLink = ChannelLink.tryParse(rawUrl);
    if (channelLink != null) {
      _pendingChannelLink = channelLink;
      flushChannelLink();
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != ChannelLink.scheme) return;
    final handler = _onProtocolUri;
    if (handler == null) {
      _pendingProtocolUri = uri;
    } else {
      handler(uri);
    }
  }

  void flushChannelLink() {
    final link = _pendingChannelLink;
    final chatController = _chatController;
    final workspaceController = _workspaceController;
    final workspace = chatController?.workspace;
    if (link == null ||
        chatController == null ||
        workspaceController == null ||
        workspace == null) {
      return;
    }
    _pendingChannelLink = null;
    if (!workspaceController.openChannelLink(workspace, link)) return;
    unawaited(chatController.openChannel(link.channelId));
  }

  void detach() {
    _chatController = null;
    _workspaceController = null;
    _onProtocolUri = null;
    _pendingChannelLink = null;
    _pendingProtocolUri = null;
  }
}
