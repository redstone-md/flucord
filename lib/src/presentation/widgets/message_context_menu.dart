import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_menu.dart';

/// What the right button offers on a message.
///
/// The same actions the hover bar carries, reachable the way Discord makes
/// them reachable. A client where the right button does nothing is one where
/// half the actions are only discoverable by hovering the exact right pixels,
/// and copying an id or a link had nowhere to live at all.
enum MessageMenuAction {
  addReaction,
  reply,
  edit,
  pin,
  forward,
  createThread,
  markUnread,
  copySelection,
  copyText,
  copyLink,
  copyId,
  delete,
}

/// Opens the menu at [position], answering what was chosen, or null.
///
/// A non-empty [selectedText] adds a Copy item for that text. [canMarkUnread]
/// says whether this transport keeps read state at all, and [canForward]
/// whether it can forward.
Future<MessageMenuAction?> showMessageContextMenu({
  required BuildContext context,
  required Offset position,
  required ChatMessage message,
  required ChannelCapabilities capabilities,
  required bool isCurrentUser,
  bool canMarkUnread = false,
  bool canForward = false,
  String selectedText = '',
}) {
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()!
          as RenderBox;
  final canDelete = isCurrentUser || capabilities.manageMessages;
  // What this account may do here. The copy rows below are always there.
  final actions = <PopupMenuEntry<MessageMenuAction>>[
    if (capabilities.addReactions)
      const FlucordMenuItem(
        key: ValueKey('message-menu-add-reaction'),
        value: MessageMenuAction.addReaction,
        icon: FlucordIcons.emoji,
        label: 'Add reaction',
      ),
    if (capabilities.sendMessages)
      const FlucordMenuItem(
        key: ValueKey('message-menu-reply'),
        value: MessageMenuAction.reply,
        icon: FlucordIcons.reply,
        label: 'Reply',
      ),
    if (isCurrentUser && message.canEdit)
      const FlucordMenuItem(
        key: ValueKey('message-menu-edit'),
        value: MessageMenuAction.edit,
        icon: FlucordIcons.edit,
        label: 'Edit message',
      ),
    if (capabilities.pinMessages)
      FlucordMenuItem(
        key: const ValueKey('message-menu-pin'),
        value: MessageMenuAction.pin,
        icon: FlucordIcons.pin,
        label: message.isPinned ? 'Unpin message' : 'Pin message',
      ),
    if (canForward && capabilities.sendMessages && message.canForward)
      const FlucordMenuItem(
        key: ValueKey('message-menu-forward'),
        value: MessageMenuAction.forward,
        icon: FlucordIcons.forward,
        label: 'Forward',
      ),
    if (capabilities.createPublicThreads)
      const FlucordMenuItem(
        key: ValueKey('message-menu-thread'),
        value: MessageMenuAction.createThread,
        icon: FlucordIcons.threads,
        label: 'Create thread',
      ),
    if (canMarkUnread)
      const FlucordMenuItem(
        key: ValueKey('message-menu-mark-unread'),
        value: MessageMenuAction.markUnread,
        icon: FlucordIcons.markUnread,
        label: 'Mark unread',
      ),
  ];
  return showMenu<MessageMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      overlay.globalToLocal(position) & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      ...actions,
      if (actions.isNotEmpty) const FlucordMenuDivider(),
      if (selectedText.isNotEmpty)
        const FlucordMenuItem(
          key: ValueKey('message-menu-copy-selection'),
          value: MessageMenuAction.copySelection,
          icon: FlucordIcons.copy,
          label: 'Copy',
        ),
      const FlucordMenuItem(
        key: ValueKey('message-menu-copy-text'),
        value: MessageMenuAction.copyText,
        icon: FlucordIcons.copy,
        label: 'Copy text',
      ),
      const FlucordMenuItem(
        key: ValueKey('message-menu-copy-link'),
        value: MessageMenuAction.copyLink,
        icon: FlucordIcons.link,
        label: 'Copy message link',
      ),
      const FlucordMenuItem(
        key: ValueKey('message-menu-copy-id'),
        value: MessageMenuAction.copyId,
        icon: FlucordIcons.id,
        label: 'Copy message ID',
      ),
      if (canDelete) ...[
        const FlucordMenuDivider(),
        const FlucordMenuItem(
          key: ValueKey('message-menu-delete'),
          value: MessageMenuAction.delete,
          icon: FlucordIcons.delete,
          label: 'Delete message',
          danger: true,
        ),
      ],
    ],
  );
}

/// Connects the selectable text inside a message row to that row's menu.
///
/// The text can sit deep in the row, in a forwarded message or an embed. A view
/// outside a row, such as a search result, finds no scope and keeps the normal
/// selection menu.
class MessageMenuScope extends InheritedWidget {
  const MessageMenuScope({
    required this.onOpen,
    required this.onSelectionChanged,
    required super.child,
    super.key,
  });

  /// Opens the row's menu at a global position.
  final ValueChanged<Offset> onOpen;

  /// Tells the row what text is selected now.
  final ValueChanged<SelectedContent?> onSelectionChanged;

  static MessageMenuScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessageMenuScope>();

  @override
  bool updateShouldNotify(MessageMenuScope oldWidget) => false;
}

/// One selection over the whole timeline, so a drag can run from one
/// message into the next, author lines and times included, as in Discord.
///
/// The message list puts a [SelectionArea] around its rows and this above
/// it. A message body inside it draws no selection area of its own, and a
/// row's menu reads what is selected from here.
class TimelineSelection extends InheritedWidget {
  const TimelineSelection({
    required this.text,
    required super.child,
    super.key,
  });

  /// The text selected in the timeline now.
  final String Function() text;

  static TimelineSelection? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TimelineSelection>();

  @override
  bool updateShouldNotify(TimelineSelection oldWidget) => false;
}

/// Takes the right mouse button before anything inside [child] can use it.
///
/// A [SelectionArea] uses that button to move the selection and open its own
/// menu. It would still do both if it only lost the gesture later, because it
/// acts after 100 ms even with the gesture undecided. So this claims the press
/// as soon as it lands, and the selection stays as it was.
///
/// Claims nest: the innermost one under the press takes it, and the ones
/// around it leave it be. So a reaction chip opens its own list inside a
/// message row that opens the message menu.
class RightClickClaim extends StatelessWidget {
  const RightClickClaim({
    required this.onPressed,
    required this.child,
    super.key,
  });

  /// Called with the global position of the press.
  final ValueChanged<Offset> onPressed;
  final Widget child;

  static bool _isRightButton(int buttons) => buttons == kSecondaryMouseButton;

  /// The press the innermost claim took. A press reaches the innermost
  /// listener first, and each new press has a new pointer id.
  static int? _claimedPointer;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (!_isRightButton(event.buttons) || event.pointer == _claimedPointer) {
        return;
      }
      _claimedPointer = event.pointer;
      onPressed(event.position);
    },
    child: RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () =>
                  EagerGestureRecognizer(allowedButtonsFilter: _isRightButton),
              (_) {},
            ),
      },
      child: child,
    ),
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
