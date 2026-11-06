import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/send_failure.dart';
import '../../application/voice_controller.dart';
import '../../application/voice_moderation.dart';
import '../../domain/voice_processing.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_menu.dart';
import 'popup_anchor.dart';
import 'profile_card.dart';
import 'profile_card_route.dart';

/// What the participant menu's rows that leave it do. A null action leaves
/// its row disabled, for a surface that cannot do it.
final class ParticipantMenuActions {
  const ParticipantMenuActions({
    this.onOpenProfile,
    this.onMessage,
    this.onMention,
  });

  final OpenProfileCard? onOpenProfile;

  /// Opens the direct message with a participant.
  final ValueChanged<String>? onMessage;

  /// Puts a mention of a participant in the open channel's composer.
  final ValueChanged<String>? onMention;
}

/// Flucord's menu for one person in a Room: what a right click on a tile, a
/// Stage tile, or a seat in the channel sidebar opens.
///
/// It carries the voice controller itself because the menu opens on a route
/// above the app's scopes, where [VoiceController] cannot be looked up. The
/// volume and mute rows act on it at once; the other rows close the menu.
///
/// A voice moderator also gets the server rows for somebody seated in a
/// guild voice channel, each only with the permission it needs there.
final class ParticipantMenu {
  const ParticipantMenu({
    required this.voice,
    required this.currentMemberId,
    this.actions = const ParticipantMenuActions(),
    this.moderation,
  });

  final VoiceController voice;

  /// Null on a session that cannot moderate, which offers no server rows.
  final VoiceModeration? moderation;

  /// This account. Its own entry has no volume or mute rows: this client
  /// does not play its own voice.
  final String currentMemberId;
  final ParticipantMenuActions actions;

  /// Whether [userId] is muted for this client, which their tile marks.
  bool isMutedForYou(String userId) => voice.isParticipantMuted(userId);

  /// Opens the menu for [userId] from the widget at [context]: at [position],
  /// in global coordinates, for a click; in the widget's middle when null, as
  /// for the context-menu key.
  Future<void> open(
    BuildContext context,
    String userId, {
    Offset? position,
  }) async {
    // Taken now: the profile card opens beside the widget once the menu has
    // closed, and Move to opens its own menu in the same place.
    final anchor = popupAnchorOf(context);
    final at = menuAt(context, position: position);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final isSelf = userId == currentMemberId;
    final copyId = ProfileCardMenuEntry.copyUserId(userId);
    VoidCallback? bound(ValueChanged<String>? action) =>
        action == null ? null : () => action(userId);
    final profile = actions.onOpenProfile;
    final seat = voice.guildSeatOf(userId);
    final server = seat == null ? null : moderation?.of(seat);
    // A refusal is said, not dropped: the row has closed by then.
    Future<void> said(String what, Future<void> request) async {
      try {
        await request;
      } on Object catch (error) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('$what failed. ${refusalOr(error, 'Try again.')}'),
          ),
        );
      }
    }

    void run(String what, Future<void> request) =>
        unawaited(said(what, request));
    await showFlucordActionMenuAt(
      context,
      at: at,
      items: [
        flucordMenuAction(
          'participant-menu-profile',
          'Profile',
          FlucordIcons.profile,
          profile == null ? null : () => profile(userId, anchor),
        ),
        // Nobody writes to themselves, as on their profile card.
        if (!isSelf)
          flucordMenuAction(
            'participant-menu-message',
            'Message',
            FlucordIcons.directMessages,
            bound(actions.onMessage),
          ),
        flucordMenuAction(
          'participant-menu-mention',
          'Mention',
          FlucordIcons.mention,
          bound(actions.onMention),
        ),
        if (!isSelf) ...[
          const FlucordMenuDivider(),
          FlucordMenuSlider(
            key: const ValueKey('participant-menu-volume'),
            label: 'User volume',
            value: voice.volumeFor(userId),
            max: VoiceListeningSettings.maxParticipantVolume,
            // The Room's own level, to find the way back to it.
            mark: 1,
            onChanged: (level) =>
                unawaited(voice.setParticipantVolume(userId, level)),
          ),
          const FlucordMenuDivider(),
          FlucordMenuCheckbox(
            key: const ValueKey('participant-menu-mute'),
            label: 'Mute',
            value: voice.isParticipantMuted(userId),
            onChanged: (muted) =>
                unawaited(voice.setParticipantMuted(userId, muted)),
          ),
          FlucordMenuCheckbox(
            key: const ValueKey('participant-menu-mute-soundboard'),
            label: 'Mute soundboard',
            value: voice.isSoundboardMuted(userId),
            onChanged: (muted) =>
                unawaited(voice.setSoundboardMuted(userId, muted)),
          ),
        ],
        if (server != null && !server.isEmpty) ...[
          const FlucordMenuDivider(),
          if (server.canMute)
            FlucordMenuCheckbox(
              key: const ValueKey('participant-menu-server-mute'),
              label: 'Server mute',
              value: server.isServerMuted,
              onChanged: (muted) =>
                  run('Server mute', server.setServerMuted(muted)),
            ),
          if (server.canDeafen)
            FlucordMenuCheckbox(
              key: const ValueKey('participant-menu-server-deafen'),
              label: 'Server deafen',
              value: server.isServerDeafened,
              onChanged: (deafened) =>
                  run('Server deafen', server.setServerDeafened(deafened)),
            ),
          if (server.moveTargets.isNotEmpty)
            FlucordMenuItem(
              key: const ValueKey('participant-menu-move'),
              label: 'Move to',
              icon: FlucordIcons.voiceChannel,
              trailing: const FlucordIcon(FlucordIcons.chevronRight),
              value: () => unawaited(
                showFlucordActionMenuAt(
                  navigator.context,
                  at: at,
                  items: [
                    for (final channel in server.moveTargets)
                      flucordMenuAction(
                        'participant-menu-move-${channel.id}',
                        channel.name,
                        FlucordIcons.voiceChannel,
                        () => run('Move', server.moveTo(channel.id)),
                      ),
                  ],
                ),
              ),
            ),
          if (server.canDisconnect)
            flucordMenuAction(
              'participant-menu-disconnect',
              'Disconnect',
              FlucordIcons.hangUp,
              () => run('Disconnect', server.disconnect()),
              danger: true,
            ),
        ],
        const FlucordMenuDivider(),
        flucordMenuAction(
          'participant-menu-copy-id',
          copyId.label,
          copyId.icon,
          copyId.onSelected,
        ),
      ],
    );
  }
}
