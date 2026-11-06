import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import '../../theme/flucord_type.dart';
import 'camera_picture.dart';
import 'context_menu_target.dart';
import 'go_live_viewer.dart';
import 'member_avatar.dart';
import 'participant_menu.dart';
import 'voice_stream_controls.dart';

class VoiceParticipantGrid extends StatelessWidget {
  const VoiceParticipantGrid({
    required this.participants,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraTextureFor,
    this.streams,
    this.onTapParticipant,
    this.compact = false,
    this.participantMenu,
    super.key,
  });

  final List<VoiceParticipant> participants;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;

  /// A tile was clicked: what puts a participant on the stage and takes them
  /// off it. Null where the room has no stage to put them on.
  final void Function(String userId)? onTapParticipant;

  /// The texture a participant's camera is drawn on, when it has a picture.
  final VideoTexture? Function(String userId)? cameraTextureFor;

  /// The streams this client has open, and the controls a tile offers for
  /// them. Null where the room was drawn without a stream plane at all.
  final VoiceStreamControls? streams;

  /// What a right click on a tile opens. Null where the room was drawn
  /// without a voice controller behind it.
  final ParticipantMenu? participantMenu;

  /// Whether the grid is a strip under a stream on the stage rather than the
  /// whole room. Same tiles, smaller, reading left to right.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Center(
        key: const ValueKey('voice-participants-empty'),
        // A short window at a large font has less height than this text needs.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlucordIcon(
                FlucordIcons.voiceCall,
                size: 32,
                color: context.surfaces.muted,
              ),
              const SizedBox(height: 10),
              Text(
                'Waiting for participants',
                style: FlucordTextRole.label.strong,
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      key: const ValueKey('voice-participant-grid'),
      // A strip reads left to right: the tiles it holds are what is left of
      // the room once a stream has taken it, not a page of their own.
      scrollDirection: compact ? Axis.horizontal : Axis.vertical,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.fromLTRB(20, 12, 20, 20),
      gridDelegate: compact
          ? const SliverGridDelegateWithMaxCrossAxisExtent(
              // Wide enough that the strip's height fits one row, so the
              // tiles scroll sideways rather than stacking and clipping.
              // The width carries a card's name and control side by side.
              maxCrossAxisExtent: 200,
              mainAxisExtent: 208,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisExtent: 184,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return VoiceParticipantTile(
          cameraTextureFor: cameraTextureFor,
          participant: participant,
          members: members,
          currentMemberId: currentMemberId,
          spaceId: spaceId,
          streams: streams,
          participantMenu: participantMenu,
          onTap: onTapParticipant,
          size: compact
              ? VoiceParticipantTileSize.compact
              : VoiceParticipantTileSize.regular,
        );
      },
    );
  }
}

/// How large a tile is drawn, which is where it is drawn: in the room's
/// grid, in the strip under the stage, or as the stage itself.
enum VoiceParticipantTileSize { compact, regular, stage }

/// One participant: their picture (self-preview, camera, or avatar), their
/// name or stream card, and whether they are speaking.
class VoiceParticipantTile extends StatelessWidget {
  const VoiceParticipantTile({
    required this.participant,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraTextureFor,
    this.streams,
    this.participantMenu,
    this.onTap,
    this.size = VoiceParticipantTileSize.regular,
    super.key,
  });

  final VoiceParticipant participant;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final VideoTexture? Function(String userId)? cameraTextureFor;
  final VoiceStreamControls? streams;

  /// What a right click, the context-menu key or Shift+F10 opens on this
  /// tile, or null where the tile has no room behind it.
  final ParticipantMenu? participantMenu;
  final void Function(String userId)? onTap;
  final VoiceParticipantTileSize size;

  bool get isCurrentUser => participant.userId == currentMemberId;

  Member get member =>
      members.where((member) => member.id == participant.userId).firstOrNull ??
      _unknownMember(participant.userId);

  VideoTexture? get cameraTexture => cameraTextureFor?.call(participant.userId);

  /// The sender's own picture, on the sender's own tile only (ADR-0001).
  VoiceSelfPreview? get selfPreview =>
      isCurrentUser ? streams?.selfPreview : null;

  double get _avatarSize => switch (size) {
    VoiceParticipantTileSize.compact => 36,
    VoiceParticipantTileSize.regular => 64,
    VoiceParticipantTileSize.stage => 128,
  };

  static Member _unknownMember(String userId) {
    final suffix = userId.length <= 6
        ? userId
        : userId.substring(userId.length - 6);
    return Member(
      id: userId,
      displayName: 'Unknown user $suffix',
      initials: '?',
      role: '',
      presence: Presence.offline,
      colorValue: 0xff4a4e50,
    );
  }

  /// Whether this participant's stream is open here, which is what the mark
  /// and the control read. Asked of each tile rather than answered once for
  /// the room, because several streams can be open at once.
  bool get isOpen => streams?.isOpen(participant.userId) ?? false;

  /// Whether the tile carries a stream card rather than a plain name.
  ///
  /// This account's own tile is the one case where the card comes from the
  /// client rather than from the roster: a share that is still starting has
  /// not been echoed back as a voice state yet.
  bool get hasStream =>
      participant.isStreaming ||
      (isCurrentUser && streams?.onStopShare != null);

  /// What is wrong with the participant's microphone, if anything, and
  /// whether this client has muted them.
  List<Widget> get _stateIcons => [
    if (participant.isDeafened)
      const _StateIcon(icon: FlucordIcons.headphonesOff, label: 'Deafened')
    else if (participant.isMuted)
      const _StateIcon(icon: FlucordIcons.micOff, label: 'Muted'),
    if (participantMenu?.isMutedForYou(participant.userId) ?? false)
      const _StateIcon(icon: FlucordIcons.volumeOff, label: 'Muted for you'),
  ];

  @override
  Widget build(BuildContext context) {
    final menu = participantMenu;
    if (menu == null) return _tile(context, focused: false);
    void openMenu([Offset? position]) =>
        unawaited(menu.open(context, participant.userId, position: position));
    // Focusable so the keyboard reaches the menu too. The keys are bound
    // above the tile's focus, where its key presses pass on their way up;
    // Escape is not bound here, so it still reaches the Room's binding.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): openMenu,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): openMenu,
      },
      child: Focus(
        child: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) => openMenu(details.globalPosition),
            child: _tile(context, focused: Focus.of(context).hasFocus),
          ),
        ),
      ),
    );
  }

  /// The Stream card of somebody else's Stream, with the Stream menu on it.
  /// This account's own Stream has no menu: it does not watch itself.
  Widget _withStreamMenu(Widget card) {
    final menu = streams?.menu;
    if (menu == null || isCurrentUser) return card;
    return ContextMenuTarget(
      onOpen: (context, position) =>
          unawaited(menu.open(context, participant.userId, position: position)),
      builder: (context, _) => card,
    );
  }

  Widget _tile(BuildContext context, {required bool focused}) {
    final surfaces = context.surfaces;
    final borderColor = participant.isSpeaking
        ? surfaces.success
        : surfaces.border;
    final onTap = this.onTap;
    return GestureDetector(
      // The card's buttons sit on top and take their own presses; anywhere
      // else on the tile is the tile.
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap(participant.userId),
      child: Semantics(
        selected: participant.isSpeaking,
        label: '${member.displayNameFor(spaceId)}, voice participant',
        child: DecoratedBox(
          key: ValueKey('voice-participant-${participant.userId}'),
          decoration: BoxDecoration(
            color: surfaces.inset,
            border: Border.all(
              color: focused ? surfaces.focusRing : borderColor,
              width: participant.isSpeaking || focused ? 2 : 1,
            ),
            borderRadius: FlucordRadius.medium,
          ),
          child: Stack(
            children: [
              if (selfPreview case final preview?)
                Positioned.fill(
                  key: ValueKey('voice-self-preview-${participant.userId}'),
                  child: ClipRRect(
                    borderRadius: FlucordRadius.small,
                    child: _SelfPreview(preview: preview),
                  ),
                )
              else if (cameraTexture case final texture?)
                Positioned.fill(
                  key: ValueKey('voice-camera-${participant.userId}'),
                  child: ClipRRect(
                    borderRadius: FlucordRadius.small,
                    child: CameraPicture(texture: texture),
                  ),
                )
              else
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    child: MemberAvatar(
                      member: member,
                      size: _avatarSize,
                      showPresence: false,
                      spaceId: spaceId,
                    ),
                  ),
                ),
              if (hasStream)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _withStreamMenu(
                    _StreamCard(
                      userId: participant.userId,
                      name: member.displayNameFor(spaceId),
                      stateIcons: _stateIcons,
                      isOpen: isOpen,
                      hasFailed:
                          streams?.hasFailed?.call(participant.userId) ?? false,
                      isOwn: isCurrentUser,
                      onWatch: isCurrentUser ? null : streams?.onWatch,
                      onStopShare: isCurrentUser ? streams?.onStopShare : null,
                    ),
                  ),
                )
              else
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 9,
                  child: Row(
                    children: [
                      Expanded(
                        child: _TileName(member.displayNameFor(spaceId)),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Text(
                          'You',
                          style: TextStyle(
                            color: context.surfaces.muted,
                            fontSize: FlucordType.caption,
                          ),
                        ),
                      ],
                      ..._stateIcons,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sender's own picture, in place of the avatar.
///
/// An error is a visible state: a tile that quietly showed nothing would read
/// as a share that is not producing pictures.
class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.preview});

  final VoiceSelfPreview preview;

  @override
  Widget build(BuildContext context) {
    final error = preview.error;
    if (error != null) {
      return ColoredBox(
        key: const ValueKey('voice-self-preview-error'),
        color: context.surfaces.inset,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlucordIcon(
                  FlucordIcons.error,
                  size: 24,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 6),
                Text(
                  'Self-preview unavailable',
                  textAlign: TextAlign.center,
                  style: FlucordTextRole.caption.strong.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return GoLiveViewer(
      key: const ValueKey('voice-self-preview'),
      textures: preview.textures,
      label: 'your stream',
      showProgress: false,
    );
  }
}

/// The card a streaming participant's tile carries, in place of a name row.
///
/// A share is a connection Discord only opens when asked for, so opening one
/// has to be something to press rather than something to notice.
class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.userId,
    required this.name,
    required this.stateIcons,
    required this.isOpen,
    required this.hasFailed,
    required this.isOwn,
    this.onWatch,
    this.onStopShare,
  });

  final String userId;
  final String name;
  final List<Widget> stateIcons;
  final bool isOpen;

  /// The last watch of this stream failed. The control offers Watch again, so
  /// this is what says why nothing is showing.
  final bool hasFailed;
  final bool isOwn;

  /// Opens this participant's stream, or closes it once it is open. Null where
  /// the card has nothing to open one with.
  final void Function(String userId)? onWatch;

  /// Ends this account's own share, and the reason its tile has a card.
  final VoidCallback? onStopShare;

  /// The own stream is live as soon as Go Live is up, even while Discord is
  /// still opening the receiving connection.
  bool get showsLive => isOpen || (isOwn && onStopShare != null);

  @override
  Widget build(BuildContext context) {
    final accent = context.surfaces.danger;
    return DecoratedBox(
      key: ValueKey('voice-stream-card-$userId'),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        border: Border.all(color: showsLive ? accent : context.surfaces.border),
        borderRadius: FlucordRadius.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The mark says what is true of this tile, not what is on the
            // stage. The sender is live before its receiving connection opens.
            if (showsLive)
              _mark(
                key: 'voice-stream-open-$userId',
                icon: FlucordIcons.streaming,
                label: isOwn ? 'Live' : 'Watching',
                color: accent,
              )
            else if (hasFailed)
              _mark(
                key: 'voice-stream-error-$userId',
                icon: FlucordIcons.error,
                label: 'Stream unavailable',
                color: Theme.of(context).colorScheme.error,
              ),
            Row(
              children: [
                Expanded(child: _TileName(name)),
                ...stateIcons,
                const SizedBox(width: 4),
                _control(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One small line above the name: what is true of this stream right now.
  Widget _mark({
    required String key,
    required FlucordIconData icon,
    required String label,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlucordIcon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            key: ValueKey(key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.strong.copyWith(color: color),
          ),
        ),
      ],
    ),
  );

  Widget _control(BuildContext context) {
    if (onStopShare case final stop?) {
      return _button(
        context,
        key: 'voice-stop-share-$userId',
        label: 'Stop sharing',
        tooltip: 'Stop sharing your stream',
        onPressed: stop,
        danger: true,
      );
    }
    return switch (onWatch) {
      // The card is how a stream is found, and a tile that said nothing is how
      // it was missed.
      null => Text(
        'Streaming',
        key: ValueKey('voice-stream-idle-$userId'),
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: FlucordType.caption,
        ),
      ),
      final watch => _button(
        context,
        key: 'voice-watch-$userId',
        label: isOpen ? 'Stop watching' : 'Watch',
        // The name sits beside the button, not in it, so without this two
        // cards read the same to a screen reader.
        tooltip: '${isOpen ? 'Stop watching' : 'Watch'} $name',
        onPressed: () => watch(userId),
        danger: isOpen,
      ),
    };
  }

  Widget _button(
    BuildContext context, {
    required String key,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    required bool danger,
  }) => Tooltip(
    message: tooltip,
    child: TextButton(
      key: ValueKey(key),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: danger ? context.surfaces.danger : null,
        textStyle: FlucordTextRole.caption.strong,
      ),
      child: Text(label),
    ),
  );
}

class _TileName extends StatelessWidget {
  const _TileName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: FlucordTextRole.caption.strong,
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.label});

  final FlucordIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Tooltip(
        message: label,
        child: FlucordIcon(icon, size: 15, color: context.surfaces.danger),
      ),
    );
  }
}
