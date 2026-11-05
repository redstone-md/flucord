import 'dart:async';

import 'package:flutter/material.dart';

import 'streamer_mode_scope.dart';

import '../../domain/channel_link.dart';
import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import 'chat_scope.dart';
import 'discord_markdown.dart';
import 'guild_access_scope.dart';
import 'message_context_menu.dart';

class MessageContentView extends StatefulWidget {
  const MessageContentView({
    required this.body,
    required this.workspace,
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.now,
    this.textStyle,
    super.key,
  });

  final String body;
  final ChatWorkspace workspace;

  /// Where the message was sent, whose names the mentions read in. Null
  /// where no space is known, which reads each person's own name.
  final String? spaceId;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final DateTime? now;
  final TextStyle? textStyle;

  @override
  State<MessageContentView> createState() => _MessageContentViewState();
}

class _MessageContentViewState extends State<MessageContentView> {
  /// A click on the text still takes this, so the selection can work.
  final FocusNode _selectionFocus = FocusNode(
    debugLabel: 'message text selection',
  );

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Redacted here rather than where the message was stored: the mode can go
    // on and off while the same message is on screen, and the copy held by the
    // cache is the one that has to survive it being turned off again.
    final body = StreamerModeScope.redact(context, widget.body);
    final markdown = DiscordMarkdown(
      body: body,
      workspace: widget.workspace,
      spaceId: widget.spaceId,
      onSelectChannel: widget.onSelectChannel,
      now: widget.now,
      textStyle: widget.textStyle,
      onTapLink: (href) => unawaited(_openLink(context, href)),
    );
    // In the timeline, the list's one selection covers this text.
    if (TimelineSelection.maybeOf(context) != null) return markdown;
    final rowMenu = MessageMenuScope.maybeOf(context);
    // In a row, the row is the stop for Tab. A second stop on the text would
    // show nothing on screen and say nothing to a screen reader.
    _selectionFocus.skipTraversal = rowMenu != null;
    // A row takes the right button itself, so the selection's own menu does
    // not open over the row's.
    return SelectionArea(
      focusNode: _selectionFocus,
      onSelectionChanged: rowMenu?.onSelectionChanged,
      child: markdown,
    );
  }

  Future<void> _openLink(BuildContext context, String rawHref) async {
    // An invite link and a conversation link are the outside links this app
    // can act on itself, so each is offered to the access surface before
    // anything opens a browser. A conversation link is only claimed when the
    // workspace holds the channel it names: one from a server this account
    // never joined is a page the browser can still show.
    final access = GuildAccessScope.maybeOf(context);
    if (access != null) {
      final code = InviteLink.tryParseCode(rawHref);
      if (code != null) {
        access.onOpenInvite(context, code);
        return;
      }
      final messageLink = DiscordMessageLink.tryParse(rawHref);
      final openMessageLink = access.onOpenMessageLink;
      if (messageLink != null && openMessageLink != null) {
        final channel = ChatScope.workspaceNow(
          context,
          widget.workspace,
        ).channelOrNull(messageLink.channelId);
        if (channel != null && channel.spaceId == messageLink.spaceId) {
          openMessageLink(context, messageLink);
          return;
        }
      }
    }
    final uri = Uri.tryParse(rawHref);
    final opened = uri != null && await widget.linkLauncher.open(uri);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The link could not be opened.')),
    );
  }
}
