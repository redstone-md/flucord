import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';

/// What the right button offers on a message.
///
/// The same actions the hover bar carries, reachable the way Discord makes
/// them reachable. A client where the right button does nothing is one where
/// half the actions are only discoverable by hovering the exact right pixels,
/// and copying an id or a link had nowhere to live at all.
enum MessageMenuAction {
  reply,
  edit,
  pin,
  forward,
  createThread,
  copyText,
  copyLink,
  copyId,
  delete,
}

/// Opens the menu at [position], answering what was chosen, or null.
Future<MessageMenuAction?> showMessageContextMenu({
  required BuildContext context,
  required Offset position,
  required ChatMessage message,
  required ChannelCapabilities capabilities,
  required bool isCurrentUser,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final canDelete = isCurrentUser || capabilities.manageMessages;
  return showMenu<MessageMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      if (capabilities.sendMessages)
        const PopupMenuItem(
          key: ValueKey('message-menu-reply'),
          value: MessageMenuAction.reply,
          child: Text('Reply'),
        ),
      if (isCurrentUser)
        const PopupMenuItem(
          key: ValueKey('message-menu-edit'),
          value: MessageMenuAction.edit,
          child: Text('Edit message'),
        ),
      if (capabilities.pinMessages)
        PopupMenuItem(
          key: const ValueKey('message-menu-pin'),
          value: MessageMenuAction.pin,
          child: Text(message.isPinned ? 'Unpin message' : 'Pin message'),
        ),
      if (capabilities.sendMessages)
        const PopupMenuItem(
          key: ValueKey('message-menu-forward'),
          value: MessageMenuAction.forward,
          child: Text('Forward'),
        ),
      if (capabilities.createPublicThreads)
        const PopupMenuItem(
          key: ValueKey('message-menu-thread'),
          value: MessageMenuAction.createThread,
          child: Text('Create thread'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        key: ValueKey('message-menu-copy-text'),
        value: MessageMenuAction.copyText,
        child: Text('Copy text'),
      ),
      const PopupMenuItem(
        key: ValueKey('message-menu-copy-link'),
        value: MessageMenuAction.copyLink,
        child: Text('Copy message link'),
      ),
      const PopupMenuItem(
        key: ValueKey('message-menu-copy-id'),
        value: MessageMenuAction.copyId,
        child: Text('Copy message ID'),
      ),
      if (canDelete) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: ValueKey('message-menu-delete'),
          value: MessageMenuAction.delete,
          child: Text('Delete message'),
        ),
      ],
    ],
  );
}

/// Discord's own link shape for a message, which is what its clients paste.
///
/// `@me` stands in for the guild on a direct message, the same way Discord
/// writes it — a DM has no guild, and a link naming an empty one resolves to
/// nothing.
String messageLink({
  required String spaceId,
  required String channelId,
  required String messageId,
}) {
  final space = spaceId.isEmpty || spaceId == 'direct-messages'
      ? '@me'
      : spaceId;
  return 'https://discord.com/channels/$space/$channelId/$messageId';
}

/// Puts [text] on the clipboard, saying nothing when there is nothing to copy.
Future<bool> copyToClipboard(String text) async {
  if (text.isEmpty) return false;
  await Clipboard.setData(ClipboardData(text: text));
  return true;
}
