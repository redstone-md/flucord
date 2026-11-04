import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/friends_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/friend_suggestion.dart';
import '../../domain/relationship_request.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'captcha_scope.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'flucord_icon_button.dart';
import 'friends_page_header.dart';
import 'popup_anchor.dart';
import 'presence_indicator.dart';
import 'profile_card_route.dart';

/// The Friends page: a header with the Online, All, Pending and Blocked
/// lists and the Add friend view, then whichever of them is chosen.
class FriendsPanel extends StatefulWidget {
  const FriendsPanel({
    required this.controller,
    this.presenceOf,
    this.onMessage,
    this.onOpenProfile,
    this.inbox,
    super.key,
  });

  final FriendsController controller;

  /// What somebody's presence is, or null where the session does not know.
  ///
  /// Read from the workspace rather than held here: the presence service
  /// already keeps it current, and a second copy would be a second thing to
  /// go stale.
  final Presence? Function(String userId)? presenceOf;

  /// Opens the DM with a friend, by user id. Without it a friend row offers
  /// no message button.
  final ValueChanged<String>? onMessage;

  /// Opens somebody's profile card, from the name on their row.
  final OpenProfileCard? onOpenProfile;

  /// The inbox button at the right end of the header.
  final Widget? inbox;

  @override
  State<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends State<FriendsPanel> {
  FriendsTab _tab = FriendsTab.online;

  @override
  void initState() {
    super.initState();
    // Read once when the panel opens. Discord serves a route for these, but
    // it is not something to poll: a suggestion is not urgent. After the
    // frame, because loading notifies, and the shell listens to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.loadSuggestions());
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('friends-panel'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FriendsPageHeader(
        selected: _tab,
        onSelected: (tab) => setState(() => _tab = tab),
        inbox: widget.inbox,
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => _tab == FriendsTab.add
              ? _AddFriendView(controller: widget.controller)
              : _RelationshipList(
                  groups: _groupsFor(_tab),
                  emptyText: _tab.empty,
                  controller: widget.controller,
                  presenceOf: widget.presenceOf,
                  onMessage: widget.onMessage,
                  onOpenProfile: widget.onOpenProfile,
                ),
        ),
      ),
    ],
  );

  /// The headed groups a list tab shows, each with its count.
  List<(String, List<DiscordRelationship>)> _groupsFor(FriendsTab tab) {
    final controller = widget.controller;
    return switch (tab) {
      FriendsTab.online => [
        (
          'Online',
          [
            for (final friend in controller.friends)
              if (widget.presenceOf?.call(friend.user.id)?.isOnline ?? false)
                friend,
          ],
        ),
      ],
      // Relationships the account never asked for are shown rather than
      // dropped: one that exists and appears nowhere is one nobody can act on.
      FriendsTab.all => [
        ('All friends', controller.friends),
        ('Other', controller.others),
      ],
      FriendsTab.pending => [('Pending', controller.requests)],
      FriendsTab.blocked => [('Blocked', controller.blocked)],
      FriendsTab.add => const [],
    };
  }
}

/// One list tab: headed groups like "Online 5", or [emptyText] when every
/// group is empty.
class _RelationshipList extends StatelessWidget {
  const _RelationshipList({
    required this.groups,
    required this.emptyText,
    required this.controller,
    this.presenceOf,
    this.onMessage,
    this.onOpenProfile,
  });

  final List<(String, List<DiscordRelationship>)> groups;
  final String emptyText;
  final FriendsController controller;
  final Presence? Function(String userId)? presenceOf;
  final ValueChanged<String>? onMessage;
  final OpenProfileCard? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final group in groups)
        if (group.$2.isNotEmpty) group,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _RequestNotice(
          controller: controller,
          onSolved: controller.solveCaptcha,
        ),
        if (shown.isEmpty)
          Padding(
            key: const ValueKey('friends-empty'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              emptyText,
              style: FlucordTextRole.label.style.copyWith(
                color: context.surfaces.muted,
              ),
            ),
          ),
        for (final (title, entries) in shown) ...[
          _SectionTitle('$title ${entries.length}'),
          for (final entry in entries)
            _RelationshipRow(
              entry: entry,
              controller: controller,
              presence: presenceOf?.call(entry.user.id),
              onMessage: onMessage,
              onOpenProfile: onOpenProfile,
            ),
        ],
      ],
    );
  }
}

/// The Add friend view: a username field, then people Discord thinks the
/// account may know.
class _AddFriendView extends StatefulWidget {
  const _AddFriendView({required this.controller});

  final FriendsController controller;

  @override
  State<_AddFriendView> createState() => _AddFriendViewState();
}

class _AddFriendViewState extends State<_AddFriendView> {
  final TextEditingController _username = TextEditingController();

  @override
  void initState() {
    super.initState();
    _username.addListener(_onTyped);
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

  bool get _canSend =>
      !widget.controller.isBusy && _username.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final surfaces = context.surfaces;
    final suggestions = controller.suggestions;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Text(
          'Add friend',
          style: FlucordTextRole.heading.style.copyWith(color: surfaces.text),
        ),
        const SizedBox(height: 4),
        Text(
          'You can add friends with their Discord username.',
          style: FlucordTextRole.label.style.copyWith(color: surfaces.muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FlucordTextField(
                fieldKey: const ValueKey('friends-add-username'),
                controller: _username,
                hintText: 'Username',
                onSubmitted: (_) {
                  if (_canSend) unawaited(_send());
                },
              ),
            ),
            const SizedBox(width: 8),
            FlucordButton(
              key: const ValueKey('friends-add'),
              label: 'Send request',
              kind: FlucordButtonKind.primary,
              onPressed: _canSend ? () => unawaited(_send()) : null,
            ),
          ],
        ),
        _RequestNotice(controller: controller, onSolved: _solveCaptcha),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('You may know ${suggestions.length}'),
          for (final suggestion in suggestions)
            _SuggestionRow(suggestion: suggestion, controller: controller),
        ],
      ],
    );
  }

  Future<void> _send() async {
    final accepted = await widget.controller.addFriendByUsername(
      _username.text,
    );
    if (accepted) _username.clear();
  }

  /// A captcha met here held back the name in the field, so a solved one
  /// that goes through clears the field as a plain send does.
  Future<void> _solveCaptcha(String key) async {
    final accepted = await widget.controller.solveCaptcha(key);
    if (accepted) _username.clear();
  }
}

/// How the last request ended when it did not go through: the captcha
/// Discord wants solved, why Discord refused, or that it failed.
class _RequestNotice extends StatelessWidget {
  const _RequestNotice({required this.controller, required this.onSolved});

  final FriendsController controller;
  final Future<void> Function(String key) onSolved;

  @override
  Widget build(BuildContext context) {
    final caption = FlucordTextRole.caption.style;
    final surfaces = context.surfaces;
    if (controller.captcha case final challenge?) {
      return Padding(
        key: const ValueKey('friends-captcha'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Discord wants you to solve a captcha before it sends this.',
              style: caption.copyWith(color: surfaces.text),
            ),
            const SizedBox(height: 8),
            CaptchaScope.of(context)(challenge, onSolved),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('friends-captcha-cancel'),
                onPressed: controller.cancelCaptcha,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      );
    }
    final (key, text) = switch ((controller.refusal, controller.error)) {
      (final refusal?, _) => (
        const ValueKey('friends-refused'),
        _refusalText(refusal.reason),
      ),
      (_, _?) => (
        const ValueKey('friends-error'),
        'Something went wrong while talking to Discord. Try again.',
      ),
      _ => (null, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: caption.copyWith(color: surfaces.danger)),
    );
  }

  static String _refusalText(RelationshipRefusal reason) => switch (reason) {
    RelationshipRefusal.unknownUser =>
      'Nobody has that username. Check the spelling and try again.',
    RelationshipRefusal.alreadyFriends => 'You are already friends.',
    RelationshipRefusal.notAccepting =>
      'This person is not accepting friend requests.',
    RelationshipRefusal.bot => 'Bots cannot be added as friends.',
    RelationshipRefusal.self => 'You cannot add yourself as a friend.',
    RelationshipRefusal.friendLimit =>
      'You have reached the limit of 1,000 friends.',
    RelationshipRefusal.unverifiedAccount =>
      'Verify your account with Discord to send friend requests.',
    RelationshipRefusal.limited =>
      'Discord has limited your friend requests for now.',
    RelationshipRefusal.noIncomingRequest =>
      'That request is no longer waiting for you.',
    RelationshipRefusal.tooManyRequests =>
      'You are sending requests too fast. Wait a moment and try again.',
    RelationshipRefusal.other => 'Discord refused the request.',
  };
}

/// A list's caption heading, such as "Online 5".
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Text(
      text,
      style: FlucordTextRole.caption.style.copyWith(
        color: context.surfaces.captionText,
      ),
    ),
  );
}

class _RelationshipRow extends StatelessWidget {
  const _RelationshipRow({
    required this.entry,
    required this.controller,
    this.presence,
    this.onMessage,
    this.onOpenProfile,
  });

  final DiscordRelationship entry;
  final FriendsController controller;
  final Presence? presence;
  final ValueChanged<String>? onMessage;
  final OpenProfileCard? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final onMessage = this.onMessage;
    return Container(
      key: ValueKey('friend-${entry.user.id}'),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: FlucordRadius.small,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _identity(context),
            ),
          ),
          if (onMessage != null && entry.kind == DiscordRelationshipKind.friend)
            FlucordIconButton(
              key: ValueKey('friend-message-${entry.user.id}'),
              icon: FlucordIcons.chat,
              tooltip: 'Message',
              onPressed: () => onMessage(entry.user.id),
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
  }

  /// The status and the name, which open the profile card beside them.
  Widget _identity(BuildContext context) {
    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (presence case final status?) ...[
          // The shared indicator rather than a coloured dot: it paints a
          // distinct shape per status, which is what keeps the four apart
          // for somebody who cannot separate green from red.
          PresenceIndicator(
            key: ValueKey('friend-presence-${entry.user.id}'),
            presence: UserPresence(status: status),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.user.displayName,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.strong,
              ),
              Text(
                _describe(entry.kind),
                style: TextStyle(
                  fontSize: FlucordType.caption,
                  color: context.surfaces.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final open = onOpenProfile;
    if (open == null) return identity;
    return Builder(
      builder: (context) => InkWell(
        key: ValueKey('friend-profile-${entry.user.id}'),
        onTap: () => open(entry.user.id, popupAnchorOf(context)),
        borderRadius: FlucordRadius.small,
        child: identity,
      ),
    );
  }

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
        borderRadius: FlucordRadius.small,
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
                  style: FlucordTextRole.label.strong,
                ),
                if (reason.isNotEmpty)
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: FlucordType.caption,
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
                : () => unawaited(controller.befriend(suggestion.userId)),
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
