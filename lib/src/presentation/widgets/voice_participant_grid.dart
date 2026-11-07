import 'dart:async';

import 'package:flutter/material.dart';

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
import 'stream_full_screen.dart';
import 'voice_stream_controls.dart';

/// What one tile of the Room shows: a participant, or the Stream they send.
enum VoiceTileKind { person, stream }

/// One tile of the Room. A participant who sends a Stream has two, as in
/// Discord: their own, and their Stream's right after it.
typedef VoiceRoomTile = ({VoiceParticipant participant, VoiceTileKind kind});

class VoiceParticipantGrid extends StatelessWidget {
  const VoiceParticipantGrid({
    required this.tiles,
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

  /// Every tile of [participants], in order: each person, then their Stream
  /// when they send one.
  static List<VoiceRoomTile> tilesOf(
    Iterable<VoiceParticipant> participants, {
    required String currentMemberId,
    VoiceStreamControls? streams,
  }) => [
    for (final participant in participants) ...[
      (participant: participant, kind: VoiceTileKind.person),
      if (_sendsStream(participant, currentMemberId, streams))
        (participant: participant, kind: VoiceTileKind.stream),
    ],
  ];

  /// This account's own Stream is the one case read from the client rather
  /// than the roster: a share that is still starting has not been echoed
  /// back as a voice state yet.
  static bool _sendsStream(
    VoiceParticipant participant,
    String currentMemberId,
    VoiceStreamControls? streams,
  ) =>
      participant.isStreaming ||
      (participant.userId == currentMemberId && streams?.onStopShare != null);

  final List<VoiceRoomTile> tiles;
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

  /// Whether the grid is the strip under the Stage rather than the whole
  /// room. Same tiles, smaller, in one row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) {
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
    // A person whose Stream has no tile here, because it is on the Stage,
    // carries the LIVE mark on their own tile instead.
    final streamTiles = {
      for (final tile in tiles)
        if (tile.kind == VoiceTileKind.stream) tile.participant.userId,
    };
    final size = compact
        ? VoiceParticipantTileSize.compact
        : VoiceParticipantTileSize.regular;
    // Centred, so a few tiles sit in the middle of the room, as in Discord.
    return Center(
      child: GridView.builder(
        key: const ValueKey('voice-participant-grid'),
        shrinkWrap: true,
        scrollDirection: compact ? Axis.horizontal : Axis.vertical,
        padding: compact ? EdgeInsets.zero : const EdgeInsets.all(16),
        gridDelegate: compact
            // One row: the strip is exactly one tile tall.
            ? const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: stripHeight,
                mainAxisExtent: stripTileWidth,
                crossAxisSpacing: _gap,
                mainAxisSpacing: _gap,
              )
            : const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 306 / 220,
                crossAxisSpacing: _gap,
                mainAxisSpacing: _gap,
              ),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          final tile = tiles[index];
          final userId = tile.participant.userId;
          return tileFor(
            tile,
            size: size,
            live:
                _sendsStream(tile.participant, currentMemberId, streams) &&
                !streamTiles.contains(userId),
          );
        },
      ),
    );
  }

  /// Draws [tile] at [size], the one way a Room draws a tile: the grid uses
  /// it for each of its tiles, and the Room for its Stage. [live] marks a
  /// person tile whose Stream has no tile beside it. [picture] is the
  /// watched session's pictures, for a Stream on the Stage.
  ///
  /// A Stream on the Stage answers no single tap, which would hold up the
  /// double click that opens it full screen.
  Widget tileFor(
    VoiceRoomTile tile, {
    required VoiceParticipantTileSize size,
    bool live = false,
    Widget? picture,
    Key? key,
  }) => switch (tile) {
    (:final participant, kind: VoiceTileKind.person) => VoiceParticipantTile(
      key: key,
      participant: participant,
      members: members,
      currentMemberId: currentMemberId,
      spaceId: spaceId,
      cameraTextureFor: cameraTextureFor,
      participantMenu: participantMenu,
      onTap: onTapParticipant,
      size: size,
      live: live,
    ),
    (:final participant, kind: VoiceTileKind.stream) => VoiceStreamTile(
      key: key,
      participant: participant,
      members: members,
      currentMemberId: currentMemberId,
      spaceId: spaceId,
      streams: streams,
      picture: picture,
      onTap: size == VoiceParticipantTileSize.stage ? null : onTapParticipant,
      size: size,
    ),
  };

  /// How tall the strip under the Stage is, and how wide a tile in it.
  static const stripHeight = 104.0;
  static const stripTileWidth = 176.0;
  static const _gap = 8.0;
}

/// How large a tile is drawn, which is where it is drawn: in the room's
/// grid, in the strip under the stage, or as the stage itself.
enum VoiceParticipantTileSize {
  compact,
  regular,
  stage;

  double get _avatar => switch (this) {
    compact => 40,
    regular => 64,
    stage => 128,
  };

  BorderRadius get _radius =>
      this == compact ? FlucordRadius.medium : FlucordRadius.large;

  double get _inset => this == stage ? 12 : 8;
}

/// One participant: their camera or avatar in the middle, a name chip with
/// their marks in the bottom-left, and a green ring while they speak.
class VoiceParticipantTile extends StatelessWidget {
  const VoiceParticipantTile({
    required this.participant,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraTextureFor,
    this.participantMenu,
    this.onTap,
    this.size = VoiceParticipantTileSize.regular,
    this.live = false,
    super.key,
  });

  final VoiceParticipant participant;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final VideoTexture? Function(String userId)? cameraTextureFor;

  /// What a right click, the context-menu key or Shift+F10 opens on this
  /// tile, or null where the tile has no room behind it.
  final ParticipantMenu? participantMenu;
  final void Function(String userId)? onTap;
  final VoiceParticipantTileSize size;

  /// Whether the tile carries the LIVE mark: the participant sends a Stream
  /// that has no tile of its own beside this one.
  final bool live;

  bool get isCurrentUser => participant.userId == currentMemberId;

  Member get member => voiceMemberOf(members, participant.userId);

  VideoTexture? get cameraTexture => cameraTextureFor?.call(participant.userId);

  List<Widget> get _marks => [
    for (final mark in participantMarks(
      participant,
      mutedForYou: participantMenu?.isMutedForYou(participant.userId) ?? false,
    ))
      _Mark(mark),
  ];

  @override
  Widget build(BuildContext context) {
    final menu = participantMenu;
    if (menu == null) return _tile(context, hasFocus: false);
    return ContextMenuTarget(
      onOpen: (context, position) =>
          unawaited(menu.open(context, participant.userId, position: position)),
      builder: (context, hasFocus) => _tile(context, hasFocus: hasFocus),
    );
  }

  Widget _tile(BuildContext context, {required bool hasFocus}) {
    final surfaces = context.surfaces;
    final ring = hasFocus
        ? surfaces.focusRing
        : participant.isSpeaking
        ? surfaces.success
        : null;
    final onTap = this.onTap;
    final name = member.displayNameFor(spaceId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap(participant.userId),
      child: Semantics(
        selected: participant.isSpeaking,
        label: '$name, voice participant',
        child: DecoratedBox(
          key: ValueKey('voice-participant-${participant.userId}'),
          decoration: BoxDecoration(
            color: surfaces.raised,
            border: ring == null ? null : Border.all(color: ring, width: 2),
            borderRadius: size._radius,
          ),
          child: ClipRRect(
            borderRadius: size._radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cameraTexture case final texture?)
                  CameraPicture(
                    key: ValueKey('voice-camera-${participant.userId}'),
                    texture: texture,
                  )
                else
                  Center(
                    child: MemberAvatar(
                      member: member,
                      size: size._avatar,
                      showPresence: false,
                      spaceId: spaceId,
                    ),
                  ),
                if (live)
                  Positioned(
                    top: size._inset,
                    left: size._inset,
                    child: const _LiveBadge(),
                  ),
                Positioned(
                  left: size._inset,
                  right: size._inset,
                  bottom: size._inset,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _NameChip(
                      name: isCurrentUser ? '$name (you)' : name,
                      marks: _marks,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One participant's Stream, as a tile of its own.
///
/// Not watched: a LIVE badge and a "Watch stream" button in the middle.
/// Watched, or this account's own: the picture, with the button to stop it
/// in the bottom-right corner. On the Stage, [picture] is the watched
/// session's viewer.
///
/// Somebody else's Stream opens the Stream menu on a right click, the
/// context-menu key or Shift+F10. On the Stage, a double click or the
/// corner button opens it full screen.
class VoiceStreamTile extends StatelessWidget {
  const VoiceStreamTile({
    required this.participant,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.streams,
    this.picture,
    this.onTap,
    this.size = VoiceParticipantTileSize.regular,
    super.key,
  });

  /// The Sender.
  final VoiceParticipant participant;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final VoiceStreamControls? streams;

  /// The watched session's pictures, when this tile is on the Stage.
  final Widget? picture;
  final void Function(String userId)? onTap;
  final VoiceParticipantTileSize size;

  String get _userId => participant.userId;
  bool get _isOwn => _userId == currentMemberId;

  @override
  Widget build(BuildContext context) {
    final member = voiceMemberOf(members, _userId);
    final name = member.displayNameFor(spaceId);
    final streams = this.streams;
    final isOpen = streams?.isOpen(_userId) ?? false;
    // The Sender's own picture, on the Sender's own Stream tile (ADR-0001).
    final selfPreview = _isOwn ? streams?.selfPreview : null;
    final inset = size._inset;
    final onStage = size == VoiceParticipantTileSize.stage;
    final chip = _NameChip(
      name: name,
      leading: onStage
          ? MemberAvatar(
              member: member,
              size: 14,
              showPresence: false,
              spaceId: spaceId,
            )
          : null,
    );
    // This account's own Stream has no menu: it does not watch itself.
    final menu = _isOwn ? null : streams?.menu;
    final fullScreen = menu == null || !onStage
        ? null
        : () => unawaited(menu.openFullScreen(context, _userId));
    final controls = _control(
      context,
      name: name,
      isOpen: isOpen,
      fullScreen: fullScreen,
    );
    // With a double click on the tile, its buttons sit beside the tile's
    // gestures rather than inside them, so a press does not wait to learn
    // whether a second click follows.
    final controlsInside = fullScreen == null;
    Widget tile(bool hasFocus) => Semantics(
      label: "$name's stream",
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FlucordFixedColors.media,
          border: hasFocus
              ? Border.all(color: context.surfaces.focusRing, width: 2)
              : null,
          borderRadius: size._radius,
        ),
        child: ClipRRect(
          borderRadius: size._radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (picture case final picture?)
                picture
              else if (selfPreview case final preview?)
                _SelfPreview(
                  key: ValueKey('voice-self-preview-$_userId'),
                  preview: preview,
                ),
              Positioned(
                top: inset,
                left: inset,
                right: inset,
                child: Row(
                  spacing: 6,
                  children: [
                    const _LiveBadge(),
                    if (onStage) Flexible(child: chip),
                  ],
                ),
              ),
              if (!onStage)
                Positioned(
                  left: inset,
                  right: inset,
                  bottom: inset,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: chip,
                  ),
                ),
              if (controlsInside) ...controls,
            ],
          ),
        ),
      ),
    );
    final onTap = this.onTap;
    Widget tappable(bool hasFocus) => onTap == null
        ? tile(hasFocus)
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(_userId),
            child: tile(hasFocus),
          );
    final target = menu == null
        ? tappable(false)
        : ContextMenuTarget(
            key: onStage ? const ValueKey('stage-stream') : null,
            onOpen: (context, position) =>
                unawaited(menu.open(context, _userId, position: position)),
            // The Stage has no single tap, so a double click costs it no
            // delay.
            onDoubleTap: fullScreen,
            builder: (_, hasFocus) => tappable(hasFocus),
          );
    return KeyedSubtree(
      key: ValueKey('voice-stream-card-$_userId'),
      child: controlsInside
          ? target
          : Stack(fit: StackFit.expand, children: [target, ...controls]),
    );
  }

  /// What the tile offers for its Stream, and where it sits.
  List<Widget> _control(
    BuildContext context, {
    required String name,
    required bool isOpen,
    VoidCallback? fullScreen,
  }) {
    final streams = this.streams;
    final stop = switch ((_isOwn, isOpen)) {
      (true, _) => switch (streams?.onStopShare) {
        final stopShare? => _OverlayButton(
          key: ValueKey('voice-stop-share-$_userId'),
          label: 'Stop sharing',
          tooltip: 'Stop sharing your stream',
          onPressed: stopShare,
        ),
        null => null,
      },
      (false, true) => switch (streams?.onWatch) {
        final watch? => _OverlayButton(
          key: ValueKey('voice-watch-$_userId'),
          label: 'Stop watching',
          tooltip: 'Stop watching $name',
          onPressed: () => watch(_userId),
        ),
        null => null,
      },
      (false, false) => null,
    };
    if (stop != null) {
      return [
        Positioned(
          right: size._inset,
          bottom: size._inset,
          child: Row(
            spacing: 6,
            children: [
              if (fullScreen != null)
                FullScreenButton(
                  key: const ValueKey('stage-stream-full-screen'),
                  isFullScreen: false,
                  onPressed: fullScreen,
                ),
              stop,
            ],
          ),
        ),
      ];
    }
    final hasFailed = streams?.hasFailed?.call(_userId) ?? false;
    return [
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            // The control offers Watch again, so this is what says why
            // nothing is showing.
            if (hasFailed)
              Text(
                'Stream unavailable',
                key: ValueKey('voice-stream-error-$_userId'),
                style: FlucordTextRole.caption.strong.copyWith(
                  color: context.surfaces.errorText,
                ),
              ),
            switch (_isOwn ? null : streams?.onWatch) {
              final watch? => Tooltip(
                message: 'Watch $name',
                child: FilledButton.icon(
                  key: ValueKey('voice-watch-$_userId'),
                  onPressed: () => watch(_userId),
                  icon: const FlucordIcon(FlucordIcons.screenShare, size: 16),
                  label: const Text('Watch stream'),
                ),
              ),
              // A build that cannot watch, or this account's own Stream
              // sent from elsewhere, still shows the Stream is there.
              null => Text(
                'Streaming',
                key: ValueKey('voice-stream-idle-$_userId'),
                style: FlucordTextRole.caption.style.copyWith(
                  color: context.surfaces.muted,
                ),
              ),
            },
          ],
        ),
      ),
    ];
  }
}

/// One thing a person's tile, avatar or seat says about their sound.
/// [byServer] is a moderator's doing, drawn apart from the person's own.
typedef ParticipantMark = ({FlucordIconData icon, String label, bool byServer});

/// What a Room tile or a call avatar marks about [participant]'s sound, the
/// most pressing first: their microphone, then whether this client muted
/// them. [participant] is null for somebody not in the Room, whose
/// microphone is nobody's business yet.
List<ParticipantMark> participantMarks(
  VoiceParticipant? participant, {
  required bool mutedForYou,
}) => [
  if (participant != null)
    ...soundMarks(
      selfMuted: participant.selfMuted,
      selfDeafened: participant.selfDeafened,
      serverDeafened: participant.serverDeafened,
      speechBlock: participant.speechBlock,
    ),
  if (mutedForYou)
    (icon: FlucordIcons.volumeOff, label: 'Muted for you', byServer: false),
];

/// What somebody's voice state marks: deafened before muted, as deafening
/// mutes too. A [speechBlock] still shows beside a self-deafen, because only
/// a moderator or the channel can lift it.
List<ParticipantMark> soundMarks({
  required bool selfMuted,
  required bool selfDeafened,
  required bool serverDeafened,
  required SpeechBlock? speechBlock,
}) => [
  if (serverDeafened)
    (icon: FlucordIcons.headphonesOff, label: 'Server deafened', byServer: true)
  else if (selfDeafened)
    (icon: FlucordIcons.headphonesOff, label: 'Deafened', byServer: false),
  if (speechBlock != null && !serverDeafened)
    (
      icon: FlucordIcons.micOff,
      label: switch (speechBlock) {
        SpeechBlock.serverMuted => 'Server muted',
        // Only this account's own seat is judged by its permissions.
        SpeechBlock.noPermission =>
          'You do not have permission to speak in this channel',
        SpeechBlock.suppressed => 'Suppressed',
      },
      byServer: true,
    )
  else if (selfMuted && !selfDeafened && !serverDeafened)
    (icon: FlucordIcons.micOff, label: 'Muted', byServer: false),
];

/// The member [userId] names, or a stand-in for somebody this client has not
/// loaded.
Member voiceMemberOf(List<Member> members, String userId) =>
    members.where((member) => member.id == userId).firstOrNull ??
    _unknownMember(userId);

Member _unknownMember(String userId) {
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

/// The sender's own picture.
///
/// An error is a visible state: a tile that quietly showed nothing would read
/// as a share that is not producing pictures.
class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.preview, super.key});

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

/// A name on a dark chip, readable over an avatar or a picture, with the
/// participant's marks before it.
class _NameChip extends StatelessWidget {
  const _NameChip({required this.name, this.marks = const [], this.leading});

  final String name;
  final List<Widget> marks;

  /// Drawn before the marks, such as the Sender's avatar on the Stage.
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('voice-name-chip'),
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: FlucordFixedColors.scrim,
      borderRadius: FlucordRadius.medium,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        ?leading,
        ...marks,
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.strong.copyWith(
              color: context.surfaces.text,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One mark in a name chip, such as a muted microphone.
class _Mark extends StatelessWidget {
  const _Mark(this.mark);

  final ParticipantMark mark;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: mark.label,
    child: FlucordIcon(
      mark.icon,
      size: 14,
      color: mark.byServer
          ? context.surfaces.danger
          : context.surfaces.bodyText,
    ),
  );
}

/// Says a Stream is live.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.surfaces.danger,
      borderRadius: FlucordRadius.small,
    ),
    child: Text(
      'LIVE',
      style: FlucordTextRole.caption.strong.copyWith(
        color: FlucordFixedColors.onFill,
        height: 1,
      ),
    ),
  );
}

/// A button drawn over a picture, such as Stop watching.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: FlucordFixedColors.scrim,
        foregroundColor: context.surfaces.text,
        textStyle: FlucordTextRole.label.strong,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: FlucordRadius.medium),
      ),
      child: Text(label),
    ),
  );
}
