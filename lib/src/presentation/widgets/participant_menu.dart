import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/voice_controller.dart';
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
final class ParticipantMenu {
  const ParticipantMenu({
    required this.voice,
    required this.currentMemberId,
    this.actions = const ParticipantMenuActions(),
  });

  final VoiceController voice;

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
    // closed.
    final anchor = popupAnchorOf(context);
    final isSelf = userId == currentMemberId;
    final copyId = ProfileCardMenuEntry.copyUserId(userId);
    VoidCallback? bound(ValueChanged<String>? action) =>
        action == null ? null : () => action(userId);
    final profile = actions.onOpenProfile;
    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: menuAt(context, position: position),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
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
        const FlucordMenuDivider(),
        flucordMenuAction(
          'participant-menu-copy-id',
          copyId.label,
          copyId.icon,
          copyId.onSelected,
        ),
      ],
    );
    chosen?.call();
  }
}
