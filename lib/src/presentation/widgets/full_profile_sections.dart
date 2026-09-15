import 'package:flutter/material.dart';

import '../../application/member_profile_controller.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

/// The full profile underneath the identity block: pronouns, about me,
/// connections, mutual servers and friends, and the private note.
///
/// Every section is drawn only from what the fetch returned, so a profile
/// with nothing set shows nothing rather than a stack of empty headings.
/// The sections with nothing to say are absent, which is what Discord's own
/// popover does too.
class FullProfileSections extends StatelessWidget {
  const FullProfileSections({required this.controller, super.key});

  final MemberProfileController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    // The note is the one section the account owns, so it shows whatever
    // the profile fetch said. The rest wait for the fetch.
    if (profile == null) {
      return ProfileNoteSectionsOnly(controller: controller);
    }
    return Column(
      key: const ValueKey('full-profile-sections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.pronouns.isNotEmpty) ...[
          _section(context, 'PRONOUNS', Text(profile.pronouns)),
        ],
        if (profile.bio.isNotEmpty) ...[
          _section(context, 'ABOUT ME', Text(profile.bio)),
        ],
        if (profile.connections.isNotEmpty) ...[
          _section(
            context,
            'CONNECTIONS',
            ProfileConnectionRows(connections: profile.connections),
          ),
        ],
        if (profile.mutualServers.isNotEmpty) ...[
          _section(
            context,
            'MUTUAL SERVERS',
            ProfileMutualServerRows(servers: profile.mutualServers),
          ),
        ],
        if (profile.mutualFriends.isNotEmpty) ...[
          _section(
            context,
            'MUTUAL FRIENDS',
            ProfileMutualFriendRows(friends: profile.mutualFriends),
          ),
        ],
        ProfileNoteSection(controller: controller),
      ],
    );
  }

  Widget _section(BuildContext context, String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      child,
      const SizedBox(height: 14),
    ],
  );
}

/// The note section on its own, for a profile that has not arrived or was
/// refused: the note is this account's own, and hiding it because somebody
/// else's profile could not be read would hide the one control that works.
class ProfileNoteSectionsOnly extends StatelessWidget {
  const ProfileNoteSectionsOnly({required this.controller, super.key});

  final MemberProfileController controller;

  @override
  Widget build(BuildContext context) => ProfileNoteSection(
    key: const ValueKey('full-profile-note-only'),
    controller: controller,
  );
}

/// The badges the profile carries, drawn as Discord draws them: a row of
/// icon squares with a tooltip each.
///
/// [compact] bounds the row to the space beside a name and wraps there, so a
/// profile carrying many badges grows downward instead of off the card.
class ProfileBadgeRow extends StatelessWidget {
  const ProfileBadgeRow({
    required this.badges,
    this.compact = false,
    super.key,
  });

  final List<ProfileBadge> badges;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final row = Wrap(
      key: const ValueKey('profile-badges'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < badges.length; index++)
          Tooltip(
            message: badges[index].description,
            child: SizedBox.square(
              dimension: 22,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: RemoteIdentityImage(
                  url: badges[index].icon.isEmpty
                      ? null
                      : 'https://cdn.discordapp.com/badge-icons/${badges[index].icon}.png',
                  fallback: ColoredBox(
                    color: context.surfaces.inset,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (!compact) return row;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: row,
    );
  }
}

/// The connections, one row each: the service's name and the account's name
/// on it, with a check where the profile marks it verified.
class ProfileConnectionRows extends StatelessWidget {
  const ProfileConnectionRows({required this.connections, super.key});

  final List<ProfileConnection> connections;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('profile-connections'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final connection in connections)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.surfaces.inset,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      connection.type.length <= 2
                          ? connection.type.toUpperCase()
                          : connection.type.substring(0, 2).toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: context.surfaces.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (connection.verified)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.verified_outlined,
                    key: const ValueKey('profile-connection-verified'),
                    size: 14,
                    color: FlucordColors.success,
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

/// The mutual servers, one row each, with the client's own name for the
/// server where it knows one and the raw id where it does not.
class ProfileMutualServerRows extends StatelessWidget {
  const ProfileMutualServerRows({required this.servers, super.key});

  final List<MutualServer> servers;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('profile-mutual-servers'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final server in servers)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  server.nickname ?? server.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The mutual friends, one row each with the name Discord's response carries.
class ProfileMutualFriendRows extends StatelessWidget {
  const ProfileMutualFriendRows({required this.friends, super.key});

  final List<MutualFriend> friends;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('profile-mutual-friends'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final friend in friends)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  friend.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The private note this account keeps on the user, editable in place.
///
/// The field is always shown: the note is the one section the account owns,
/// and hiding it for being empty is how nobody ever learns it exists.
/// Saving a blank note removes it, which is the only way a note is removed.
class ProfileNoteSection extends StatefulWidget {
  const ProfileNoteSection({required this.controller, super.key});

  final MemberProfileController controller;

  @override
  State<ProfileNoteSection> createState() => _ProfileNoteSectionState();
}

class _ProfileNoteSectionState extends State<ProfileNoteSection> {
  late final TextEditingController _field;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: widget.controller.note ?? '');
  }

  @override
  void didUpdateWidget(covariant ProfileNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.openUserId != widget.controller.openUserId) {
      _field.text = widget.controller.note ?? '';
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      key: const ValueKey('profile-note-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'NOTE',
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('profile-note-field'),
          controller: _field,
          enabled: controller.isSupported && !controller.noteSaving,
          maxLength: 256,
          maxLines: 3,
          minLines: 1,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: controller.isSupported
                ? 'Click to add a note'
                : 'Notes need a signed-in account',
          ),
          style: const TextStyle(fontSize: 12),
        ),
        if (controller.noteRefused)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Discord did not take that note.',
              key: ValueKey('profile-note-refused'),
              style: TextStyle(fontSize: 11),
            ),
          ),
        if (_dirty && controller.isSupported)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TextButton(
                  key: const ValueKey('profile-note-discard'),
                  onPressed: () {
                    _field.text = controller.note ?? '';
                    setState(() => _dirty = false);
                  },
                  child: const Text('Discard'),
                ),
                FilledButton(
                  key: const ValueKey('profile-note-save'),
                  onPressed: controller.noteSaving
                      ? null
                      : () async {
                          await controller.saveNote(_field.text);
                          if (mounted && !controller.noteRefused) {
                            setState(() => _dirty = false);
                          }
                        },
                  child: Text(controller.noteSaving ? 'Saving…' : 'Save note'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
