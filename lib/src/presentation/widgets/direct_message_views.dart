import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/direct_message_candidate.dart';
import '../../domain/discord_snowflake.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';
import 'member_avatar.dart';
import 'remote_identity_image.dart';

/// Finds somebody to message. Pops with their user id.
class DirectMessageDialog extends StatefulWidget {
  const DirectMessageDialog({required this.people, super.key});

  /// Everybody on offer, in the order to list them.
  final List<DirectMessageCandidate> people;

  @override
  State<DirectMessageDialog> createState() => _DirectMessageDialogState();
}

class _DirectMessageDialogState extends State<DirectMessageDialog> {
  String _query = '';

  List<DirectMessageCandidate> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.people;
    return [
      for (final person in widget.people)
        if (person.matches(query)) person,
    ];
  }

  void _open(DirectMessageCandidate person) =>
      Navigator.pop(context, person.id);

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return FlucordDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('direct-message-search'),
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Search friends and members',
                prefixIcon: FlucordIcon(FlucordIcons.search, size: 16),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.isNotEmpty) _open(matches.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'Nobody found',
                        style: TextStyle(color: context.surfaces.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, index) => _PersonRow(
                        person: matches[index],
                        onPressed: () => _open(matches[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onPressed});

  final DirectMessageCandidate person;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('direct-message-person-${person.id}'),
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: SizedBox.square(
      dimension: 30,
      child: ClipOval(
        child: RemoteIdentityImage(
          url: person.avatarUrl,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: const FlucordIcon(FlucordIcons.person, size: 16),
          ),
        ),
      ),
    ),
    title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: person.isFriend ? const Text('Friend') : null,
    onTap: onPressed,
  );
}

class DirectMessagesEmptyView extends StatelessWidget {
  const DirectMessagesEmptyView({required this.onNewMessage, super.key});

  static const _iconSize = 32.0;

  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlucordIcon(
          FlucordIcons.directMessages,
          size: _iconSize,
          color: context.surfaces.muted,
        ),
        const SizedBox(height: 12),
        Text(
          'No direct messages',
          style: FlucordTextRole.heading.style.copyWith(
            color: context.surfaces.text,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onNewMessage,
          icon: const FlucordIcon(FlucordIcons.edit, size: 16),
          label: const Text('New message'),
        ),
      ],
    ),
  );
}

/// The person a DM is with, as the chat header draws them before the name:
/// a small avatar with their status dot.
class DirectMessageHeaderAvatar extends StatelessWidget {
  const DirectMessageHeaderAvatar({required this.person, super.key});

  static const size = 24.0;

  final Member person;

  @override
  Widget build(BuildContext context) => MemberAvatar(
    member: person,
    size: size,
    // The dot is cut out of the header it sits on.
    presenceBorderColor: context.surfaces.canvas,
  );
}

/// What a DM opens on, above its first message: the person, large, and a
/// line that says this is where the history starts.
class DirectMessageStart extends StatelessWidget {
  const DirectMessageStart({
    required this.avatar,
    required this.name,
    this.username,
    super.key,
  });

  /// The size [avatar] is drawn at.
  static const avatarSize = 80.0;

  final Widget avatar;
  final String name;

  /// The person's username, or null where the transport does not carry it.
  final String? username;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: avatarSize, child: avatar),
          const SizedBox(height: 12),
          Text(
            name,
            style: FlucordTextRole.display.style.copyWith(color: surfaces.text),
          ),
          if (username case final username?)
            Text(
              username,
              style: FlucordTextRole.label.style.copyWith(
                color: surfaces.muted,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'This is the beginning of your direct message history with $name.',
            style: FlucordTextRole.body.style.copyWith(color: surfaces.muted),
          ),
        ],
      ),
    );
  }
}

/// [DirectMessageProfilePanel] for a person the workspace knows.
///
/// The servers in common are the ones the workspace has seen them in, so the
/// count can be low until their memberships load. With none seen, the
/// section stays out rather than claiming there are none.
class MemberProfilePanel extends StatelessWidget {
  const MemberProfilePanel({
    required this.person,
    required this.spaces,
    super.key,
  });

  final Member person;
  final List<CommunitySpace> spaces;

  @override
  Widget build(BuildContext context) {
    final mutual = [
      for (final space in spaces)
        if (!space.isDirectMessages && person.spaceIds.contains(space.id))
          space,
    ];
    return DirectMessageProfilePanel(
      avatar: MemberAvatar(
        member: person,
        size: DirectMessageProfilePanel.avatarSize,
        presenceBorderColor: context.surfaces.surface,
      ),
      name: person.displayName,
      status: person.presence,
      memberSince: DiscordSnowflake.createdAt(person.id),
      mutualServers: mutual.isEmpty ? null : mutual,
    );
  }
}

/// Who a DM is with, in a column on the conversation's right: the person,
/// how long they have been on Discord, and the servers you share.
class DirectMessageProfilePanel extends StatelessWidget {
  const DirectMessageProfilePanel({
    required this.avatar,
    required this.name,
    this.username,
    this.status = Presence.unknown,
    this.memberSince,
    this.mutualServers,
    super.key,
  });

  static const width = 240.0;

  /// The size [avatar] is drawn at.
  static const avatarSize = 64.0;

  static const _padding = 16.0;
  static const _sectionGap = 16.0;
  static const _serverTileSize = 20.0;
  static const _serverRowHeight = 28.0;

  final Widget avatar;
  final String name;
  final String? username;
  final Presence status;

  /// When the person made their account, or null where it is not known.
  final DateTime? memberSince;

  /// The servers both accounts are in, or null where the transport cannot
  /// tell.
  final List<CommunitySpace>? mutualServers;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final muted = FlucordTextRole.label.style.copyWith(color: surfaces.muted);
    return Container(
      key: const ValueKey('dm-profile-panel'),
      width: width,
      decoration: BoxDecoration(
        color: surfaces.surface,
        border: Border(left: BorderSide(color: surfaces.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(_padding),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox.square(dimension: avatarSize, child: avatar),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: FlucordTextRole.title.style.copyWith(color: surfaces.text),
          ),
          if (username case final username?) Text(username, style: muted),
          if (status != Presence.unknown)
            Text(
              status.label,
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.captionText,
              ),
            ),
          const SizedBox(height: _sectionGap),
          Divider(height: 1, thickness: 1, color: surfaces.border),
          if (memberSince case final since?)
            _section(
              context,
              'Member since',
              Text(
                MaterialLocalizations.of(
                  context,
                ).formatFullDate(since.toLocal()),
                style: FlucordTextRole.label.style.copyWith(
                  color: surfaces.text,
                ),
              ),
            ),
          if (mutualServers case final servers?)
            _section(
              context,
              'Mutual servers ${servers.length}',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final server in servers) _serverRow(context, server),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String heading, Widget body) => Padding(
    padding: const EdgeInsets.only(top: _sectionGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: FlucordTextRole.caption.style.copyWith(
            color: context.surfaces.captionText,
          ),
        ),
        const SizedBox(height: 4),
        body,
      ],
    ),
  );

  Widget _serverRow(BuildContext context, CommunitySpace server) {
    final surfaces = context.surfaces;
    return SizedBox(
      key: ValueKey('dm-profile-server-${server.id}'),
      height: _serverRowHeight,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: FlucordRadius.small,
            child: SizedBox.square(
              dimension: _serverTileSize,
              child: RemoteIdentityImage(
                url: server.iconUrl,
                fallback: ColoredBox(color: Color(server.colorValue)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.label.style.copyWith(color: surfaces.text),
            ),
          ),
        ],
      ),
    );
  }
}
