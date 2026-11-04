import 'package:flutter/widgets.dart';

import '../../application/chat_controller.dart';
import '../../domain/chat_models.dart';

/// Hands each widget the live presence of the people it shows.
///
/// A presence fold does not notify the chat controller, so the shell does not
/// rebuild for it. Instead each widget that shows a person reads them through
/// here, and only the widgets that show somebody whose presence moved are
/// built again. Without a scope above, a widget shows what it was given.
class PresenceScope extends StatefulWidget {
  const PresenceScope({required this.chat, required this.child, super.key});

  final ChatController chat;
  final Widget child;

  /// [member] with the presence the app holds for them now. [context] is
  /// built again when that presence changes.
  static Member memberOf(BuildContext context, Member member) {
    final scope = InheritedModel.inheritFrom<_PresenceModel>(
      context,
      aspect: member.id,
    );
    final live = scope?.chat.workspace?.memberOrNull(member.id)?.presenceDetail;
    return live == null || member.hasPresence(live)
        ? member
        : member.withPresence(live);
  }

  /// Whether [member] is online now. [context] is built again only when they
  /// go online or offline, not for a new activity.
  static bool isOnline(BuildContext context, Member member) {
    final scope = InheritedModel.inheritFrom<_PresenceModel>(
      context,
      aspect: _Online(member.id),
    );
    final live = scope?.chat.workspace?.memberOrNull(member.id);
    return (live ?? member).presence.isOnline;
  }

  /// Builds [context] again when the presence of any of [userIds] changes,
  /// for a widget that reads presences through the workspace.
  static void watch(BuildContext context, Iterable<String> userIds) {
    for (final id in userIds) {
      InheritedModel.inheritFrom<_PresenceModel>(context, aspect: id);
    }
  }

  @override
  State<PresenceScope> createState() => _PresenceScopeState();
}

class _PresenceScopeState extends State<PresenceScope> {
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    widget.chat.presenceChanges.addListener(_moved);
  }

  @override
  void didUpdateWidget(PresenceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat == widget.chat) return;
    oldWidget.chat.presenceChanges.removeListener(_moved);
    widget.chat.presenceChanges.addListener(_moved);
  }

  @override
  void dispose() {
    widget.chat.presenceChanges.removeListener(_moved);
    super.dispose();
  }

  void _moved() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final changes = widget.chat.presenceChanges;
    return _PresenceModel(
      chat: widget.chat,
      revision: _revision,
      moved: changes.moved,
      flipped: changes.flipped,
      child: widget.child,
    );
  }
}

/// Depends on whether somebody is online, not on the rest of their presence.
final class _Online {
  const _Online(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is _Online && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _PresenceModel extends InheritedModel<Object> {
  const _PresenceModel({
    required this.chat,
    required this.revision,
    required this.moved,
    required this.flipped,
    required super.child,
  });

  final ChatController chat;
  final int revision;
  final Set<String> moved;
  final Set<String> flipped;

  @override
  bool updateShouldNotify(_PresenceModel oldWidget) =>
      revision != oldWidget.revision || chat != oldWidget.chat;

  @override
  bool updateShouldNotifyDependent(
    _PresenceModel oldWidget,
    Set<Object> dependencies,
  ) {
    if (chat != oldWidget.chat) return true;
    return dependencies.any(
      (aspect) => switch (aspect) {
        _Online(:final id) => flipped.contains(id),
        final String id => moved.contains(id),
        _ => false,
      },
    );
  }
}
