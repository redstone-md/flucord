import 'package:flutter/widgets.dart';

import '../../domain/channel_link.dart';

/// Publishes the server-access surface to widgets deep in the tree.
///
/// A message that contains a Discord invite link is where the app's own join
/// flow begins, and a message or channel link is where its navigation begins;
/// the link tap happens inside the markdown renderer, far below the shell
/// that owns the dialogs and the selection. A scope keeps that reach honest:
/// a host that installs no scope (the single-pane widget tests) simply keeps
/// the external launcher behaviour for every link.
final class GuildAccessScope extends InheritedWidget {
  const GuildAccessScope({
    required this.onOpenInvite,
    required this.onOpenMessageLink,
    required super.child,
    super.key,
  });

  /// Opens the join surface with [code] already resolved in.
  final void Function(BuildContext context, String code) onOpenInvite;

  /// Routes a conversation link the app can act on itself. Null when the host
  /// offers no navigation surface, which leaves the launcher as the only way
  /// a link can be answered.
  final void Function(BuildContext context, DiscordMessageLink link)?
  onOpenMessageLink;

  @override
  bool updateShouldNotify(GuildAccessScope oldWidget) =>
      oldWidget.onOpenInvite != onOpenInvite ||
      oldWidget.onOpenMessageLink != onOpenMessageLink;

  static GuildAccessScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GuildAccessScope>();
}
