import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import '../../theme/flucord_type.dart';
import 'voice_participant_grid.dart';
import 'voice_room_controls.dart';
import 'voice_room_status.dart';
import 'voice_stream_controls.dart';
import '../../domain/voice_connection.dart';
import 'member_avatar.dart';
import 'participant_menu.dart';

class VoiceRoomView extends StatefulWidget {
  const VoiceRoomView({
    required this.guildId,
    required this.channelId,
    required this.channelName,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    this.stageControls,
    this.soundboard,
    this.goLive,
    this.camera,
    this.streamViewer,
    this.streams,
    this.participantMenu,
    this.cameraTextureFor,
    this.focusedUserId,
    this.onTapParticipant,
    this.onClearFocus,
    this._spaceId,
    super.key,
  });

  /// Null for a call in a DM or group DM, which has no guild. The room is
  /// otherwise identical — same grid, same devices, same toolbar — so the two
  /// share this widget instead of a second copy that could drift.
  final String? guildId;
  final String channelId;
  final String channelName;
  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;

  /// The texture a participant's camera is drawn on, when it has a picture.
  final VideoTexture? Function(String userId)? cameraTextureFor;

  /// The stage strip, or null for an ordinary voice channel.
  final Widget? stageControls;

  /// The soundboard button, or null where there is nothing to play into.
  final Widget? soundboard;

  /// The Go Live control, or null outside a server voice channel.
  final Widget? goLive;

  /// The account's own camera, when this build can send one.
  final SelfVideoController? camera;

  /// Somebody else's stream, drawn on the stage above the participant grid
  /// while it is being watched, or null when there is none.
  ///
  /// Null is what shrinks the grid into a strip, so it must be null and not
  /// a viewer that draws nothing: an empty box cannot be told apart from one
  /// showing a stream, and a room that thought it was always showing one
  /// never reached the grid. Asked for is not on the stage either: an ask
  /// Discord never answers must not take the room away.
  final Widget? streamViewer;

  /// Whose tile the stage draws large when no stream of theirs is on it, and
  /// what a click on a tile, or Escape, does about it.
  final String? focusedUserId;
  final void Function(String userId)? onTapParticipant;
  final VoidCallback? onClearFocus;

  /// The streams this client has open, and the controls the tiles offer for
  /// them.
  final VoiceStreamControls? streams;

  /// What a right click on a tile opens, or null where the pane behind the
  /// room has no voice controller to hand it.
  final ParticipantMenu? participantMenu;

  /// Which space's per-guild avatars to render. Defaults to [guildId] because
  /// for guild voice they are the same thing; a DM call has to supply the DM
  /// pseudo-space itself.
  final String? _spaceId;

  String get spaceId => _spaceId ?? guildId ?? '';

  @override
  State<VoiceRoomView> createState() => _VoiceRoomViewState();
}

class _VoiceRoomViewState extends State<VoiceRoomView> {
  /// Whether this account is in the channel the view is showing.
  ///
  /// Opening a voice channel does not join it, which is what Discord does:
  /// clicking one shows who is inside and offers a button. Joining on sight
  /// meant walking past a channel opened the microphone and announced the
  /// account to everybody in it.
  bool get _isInThisChannel =>
      widget.controller.connectedChannelId == widget.channelId;

  Future<void> _connect() {
    final guildId = widget.guildId;
    return guildId == null
        ? widget.controller.connectToCall(channelId: widget.channelId)
        : widget.controller.connect(
            guildId: guildId,
            channelId: widget.channelId,
          );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!_isInThisChannel) {
          return _VoiceChannelPreview(
            channelName: widget.channelName,
            seated:
                widget.controller.seatedByChannel[widget.channelId] ?? const [],
            members: widget.members,
            spaceId: widget.spaceId,
            isBusy: widget.controller.isBusy,
            onJoin: () => unawaited(_connect()),
          );
        }
        // No device panel: which microphone to use is a property of the
        // machine, and a permanent quarter of the room spent on two dropdowns
        // was width taken from the people in the channel. It lives in
        // settings, under Voice & Video.
        return Column(
          children: [
            Expanded(
              child: _VoiceStage(
                streamViewer: widget.streamViewer,
                streams: widget.streams,
                participantMenu: widget.participantMenu,
                focusedUserId: widget.focusedUserId,
                onTapParticipant: widget.onTapParticipant,
                onClearFocus: widget.onClearFocus,
                stageControls: widget.stageControls,
                controller: widget.controller,
                members: widget.members,
                currentMemberId: widget.currentMemberId,
                spaceId: widget.spaceId,
                cameraTextureFor: widget.cameraTextureFor,
              ),
            ),
            VoiceRoomControls(
              controller: widget.controller,
              camera: widget.camera,
              goLive: widget.goLive,
              soundboard: widget.soundboard,
            ),
          ],
        );
      },
    );
  }
}

/// A voice channel that has been opened but not joined.
///
/// What Discord shows: who is inside, and a button. The client is not in the
/// channel until it is pressed — nobody is announced, and no microphone is
/// opened, by looking.
class _VoiceChannelPreview extends StatelessWidget {
  const _VoiceChannelPreview({
    required this.channelName,
    required this.seated,
    required this.members,
    required this.spaceId,
    required this.isBusy,
    required this.onJoin,
  });

  final String channelName;
  final List<VoiceParticipantStateEvent> seated;
  final List<Member> members;
  final String spaceId;
  final bool isBusy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final memberById = {for (final member in members) member.id: member};
    return Center(
      key: const ValueKey('voice-channel-preview'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlucordIcon(
            FlucordIcons.voiceChannel,
            size: 30,
            color: context.surfaces.muted,
          ),
          const SizedBox(height: 10),
          Text(channelName, style: FlucordTextRole.heading.style),
          const SizedBox(height: 6),
          Text(
            seated.isEmpty
                ? 'No one is in the voice channel right now'
                : '${seated.length} in the channel',
            style: TextStyle(
              fontSize: FlucordType.caption,
              color: context.surfaces.muted,
            ),
          ),
          if (seated.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Who is inside, before deciding to walk in — which is the reason
            // Discord shows this screen rather than joining on sight.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final participant in seated.take(12))
                  if (memberById[participant.userId] case final member?)
                    MemberAvatar(
                      key: ValueKey('voice-preview-${participant.userId}'),
                      member: member,
                      size: 34,
                      showPresence: false,
                      spaceId: spaceId,
                    ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('voice-channel-join'),
            onPressed: isBusy ? null : onJoin,
            icon: const FlucordIcon(FlucordIcons.call, size: 16),
            label: const Text('Join voice channel'),
          ),
        ],
      ),
    );
  }
}

class _VoiceStage extends StatelessWidget {
  const _VoiceStage({
    required this.streamViewer,
    required this.stageControls,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraTextureFor,
    this.streams,
    this.participantMenu,
    this.focusedUserId,
    this.onTapParticipant,
    this.onClearFocus,
  });

  /// The texture a participant's camera is drawn on, when it has a picture.
  final VideoTexture? Function(String userId)? cameraTextureFor;
  final String? focusedUserId;
  final void Function(String userId)? onTapParticipant;
  final VoidCallback? onClearFocus;

  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final Widget? stageControls;
  final Widget? streamViewer;
  final VoiceStreamControls? streams;
  final ParticipantMenu? participantMenu;

  @override
  Widget build(BuildContext context) {
    if (controller.state == VoiceState.loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    Widget grid(List<VoiceRoomTile> tiles, {required bool compact}) =>
        VoiceParticipantGrid(
          tiles: tiles,
          members: members,
          currentMemberId: currentMemberId,
          spaceId: spaceId,
          cameraTextureFor: cameraTextureFor,
          streams: streams,
          participantMenu: participantMenu,
          onTapParticipant: onTapParticipant,
          compact: compact,
        );
    final tiles = VoiceParticipantGrid.tilesOf(
      controller.participants,
      currentMemberId: currentMemberId,
      streams: streams,
    );
    // What the Stage draws: the focused participant's Stream while it is
    // arriving, else their own tile, large. A focus on somebody who has just
    // left draws nothing until the room catches up.
    final focused = controller.participants
        .where((participant) => participant.userId == focusedUserId)
        .firstOrNull;
    final VoiceRoomTile? onStage = focused == null
        ? null
        : (
            participant: focused,
            kind: streamViewer == null
                ? VoiceTileKind.person
                : VoiceTileKind.stream,
          );
    final stage = switch (onStage) {
      null => null,
      (:final participant, kind: VoiceTileKind.person) => VoiceParticipantTile(
        key: const ValueKey('voice-stage-tile'),
        participant: participant,
        members: members,
        currentMemberId: currentMemberId,
        spaceId: spaceId,
        cameraTextureFor: cameraTextureFor,
        participantMenu: participantMenu,
        onTap: onTapParticipant,
        size: VoiceParticipantTileSize.stage,
      ),
      (:final participant, kind: VoiceTileKind.stream) => VoiceStreamTile(
        participant: participant,
        members: members,
        currentMemberId: currentMemberId,
        spaceId: spaceId,
        streams: streams,
        picture: streamViewer,
        size: VoiceParticipantTileSize.stage,
      ),
    };
    // Every other tile sits in the strip under the Stage. A strip with
    // nothing left in it is not drawn at all.
    final strip = [
      for (final tile in tiles)
        if (tile.participant.userId != onStage?.participant.userId ||
            tile.kind != onStage?.kind)
          tile,
    ];
    final onClearFocus = this.onClearFocus;
    final room = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What is wrong, rather than the old fixed sentence: a room that says
        // nothing is indistinguishable from one that is simply quiet.
        if (voiceRoomWarning(controller) case final warning?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            // A long warning scrolls on a short window, so the tiles keep their
            // place.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 64),
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        warning,
                        key: const ValueKey('voice-room-warning'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: FlucordType.caption,
                        ),
                      ),
                    ),
                    if (voiceRoomOffersConnectionRetry(controller))
                      TextButton(
                        key: const ValueKey('voice-room-retry-connection'),
                        onPressed: () =>
                            unawaited(controller.retryConnection()),
                        child: const Text('Try again'),
                      ),
                    // Offered here because the alternative was leaving the
                    // channel and coming back, which is not an obvious way to
                    // ask a client to look for a headset again.
                    if (voiceRoomOffersDeviceRetry(controller))
                      TextButton(
                        key: const ValueKey('voice-room-retry-devices'),
                        onPressed: () => unawaited(controller.retryDevices()),
                        child: const Text('Try devices again'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ?stageControls,
        Expanded(
          child: stage == null
              ? grid(tiles, compact: false)
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Expanded(child: stage),
                      if (strip.isNotEmpty)
                        SizedBox(
                          height: VoiceParticipantGrid.stripHeight,
                          child: grid(strip, compact: true),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
    // The same wrapper whether or not there is a stage: a root that changed
    // shape remounted every tile and viewer on each click. Escape reaches
    // the binding while the room holds the keyboard focus, which it takes
    // when it appears.
    return CallbackShortcuts(
      bindings: {
        if (stage != null && onClearFocus != null)
          const SingleActivator(LogicalKeyboardKey.escape): onClearFocus,
      },
      child: Focus(autofocus: true, child: room),
    );
  }
}
