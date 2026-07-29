import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/friends_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/friend_suggestion.dart';
import '../../theme/flucord_theme.dart';
import 'presence_indicator.dart';

/// The account's friends, requests and blocks.
///
/// Requests come first: they are the entries that want an answer, and burying
/// them under a long friend list is how somebody misses one for a week.
class FriendsPanel extends StatefulWidget {
  const FriendsPanel({required this.controller, this.presenceOf, super.key});

  final FriendsController controller;

  /// What somebody's presence is, or null where the session does not know.
  ///
  /// Read from the workspace rather than held here: the presence service
  /// already keeps it current, and a second copy would be a second thing to
  /// go stale.
  final Presence? Function(String userId)? presenceOf;

  @override
  State<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends State<FriendsPanel> {
  final TextEditingController _username = TextEditingController();

  @override
  void initState() {
    super.initState();
    _username.addListener(_onTyped);
    // Read once when the panel opens. Discord serves a route for these, but
    // it is not something to poll: a suggestion is not urgent.
    unawaited(widget.controller.loadSuggestions());
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _username
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final requests = controller.requests;
      final friends = controller.friends;
      final blocked = controller.blocked;
      final others = controller.others;
      final suggestions = controller.suggestions;
      return Column(
        key: const ValueKey('friends-panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('friends-add-username'),
                    controller: _username,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Add by username',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  key: const ValueKey('friends-add'),
                  onPressed: controller.isBusy || _username.text.trim().isEmpty
                      ? null
                      : () => unawaited(_add(controller)),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          if (controller.lastRequestRefused)
            Padding(
              key: const ValueKey('friends-refused'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                // Somebody with requests off is a fact about them, not a
                // failure here, so it reads as one.
                'Discord would not send that request.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                if (requests.isNotEmpty)
                  _Group(
                    title: 'Requests',
                    entries: requests,
                    controller: controller,
                    presenceOf: widget.presenceOf,
                  ),
                if (friends.isNotEmpty)
                  _Group(
                    title: 'Friends',
                    entries: friends,
                    controller: controller,
                    presenceOf: widget.presenceOf,
                  ),
                if (blocked.isNotEmpty)
                  _Group(
                    title: 'Blocked',
                    entries: blocked,
                    controller: controller,
                    presenceOf: widget.presenceOf,
                  ),
                if (others.isNotEmpty)
                  _Group(
                    title: 'Other',
                    entries: others,
                    controller: controller,
                  ),
                if (suggestions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Text(
                      'You may know — ${suggestions.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.surfaces.muted,
                      ),
                    ),
                  ),
                  for (final suggestion in suggestions)
                    _SuggestionRow(
                      suggestion: suggestion,
                      controller: controller,
                    ),
                ],
                if (requests.isEmpty &&
                    friends.isEmpty &&
                    blocked.isEmpty &&
                    others.isEmpty &&
                    suggestions.isEmpty)
                  Padding(
                    key: const ValueKey('friends-empty'),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Nobody yet.',
                      style: TextStyle(color: context.surfaces.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _add(FriendsController controller) async {
    final username = _username.text;
    final accepted = await controller.addFriend(username);
    if (accepted) _username.clear();
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.entries,
    required this.controller,
    this.presenceOf,
  });

  final String title;
  final List<DiscordRelationship> entries;
  final FriendsController controller;
  final Presence? Function(String userId)? presenceOf;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(
          '$title — ${entries.length}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.surfaces.muted,
          ),
        ),
      ),
      for (final entry in entries)
        _RelationshipRow(
          entry: entry,
          controller: controller,
          presence: presenceOf?.call(entry.user.id),
        ),
    ],
  );
}

class _RelationshipRow extends StatelessWidget {
  const _RelationshipRow({
    required this.entry,
    required this.controller,
    this.presence,
  });

  final DiscordRelationship entry;
  final FriendsController controller;
  final Presence? presence;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('friend-${entry.user.id}'),
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: context.surfaces.raised,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        if (presence case final status?) ...[
          // The shared indicator rather than a coloured dot: it paints a
          // distinct shape per status, which is what keeps the four apart for
          // somebody who cannot separate green from red.
          PresenceIndicator(
            key: ValueKey('friend-presence-${entry.user.id}'),
            presence: UserPresence(status: status),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.user.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                _describe(entry.kind),
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ],
          ),
        ),
        // Accepting is the same call as asking: Discord treats a request to
        // somebody who already asked as the acceptance.
        if (entry.kind == DiscordRelationshipKind.incomingRequest)
          TextButton(
            key: ValueKey('friend-accept-${entry.user.id}'),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(controller.acceptRequest(entry)),
            child: const Text('Accept'),
          ),
        TextButton(
          key: ValueKey('friend-remove-${entry.user.id}'),
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.remove(entry)),
          child: Text(_removeLabel(entry.kind)),
        ),
      ],
    ),
  );

  static String _describe(DiscordRelationshipKind kind) => switch (kind) {
    DiscordRelationshipKind.friend => 'Friend',
    DiscordRelationshipKind.incomingRequest => 'Wants to be friends',
    DiscordRelationshipKind.outgoingRequest => 'Request sent',
    DiscordRelationshipKind.blocked => 'Blocked',
    DiscordRelationshipKind.implicit => 'You play together',
    DiscordRelationshipKind.unknown => 'Unknown',
  };

  static String _removeLabel(DiscordRelationshipKind kind) => switch (kind) {
    DiscordRelationshipKind.incomingRequest => 'Ignore',
    DiscordRelationshipKind.outgoingRequest => 'Cancel',
    DiscordRelationshipKind.blocked => 'Unblock',
    _ => 'Remove',
  };
}

/// One person Discord thinks the account may know.
///
/// Two answers only: ask them, or say no. There is no relationship yet, so
/// there is nothing else that could be done to one.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.controller});

  final FriendSuggestion suggestion;
  final FriendsController controller;

  @override
  Widget build(BuildContext context) {
    final reason = suggestion.describeReason();
    return Container(
      key: ValueKey('suggestion-${suggestion.userId}'),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (reason.isNotEmpty)
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.surfaces.muted,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('suggestion-add-${suggestion.userId}'),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(controller.addFriend(suggestion.userId)),
            child: const Text('Add'),
          ),
          TextButton(
            key: ValueKey('suggestion-dismiss-${suggestion.userId}'),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(controller.dismissSuggestion(suggestion)),
            child: const Text('No'),
          ),
        ],
      ),
    );
  }
}
