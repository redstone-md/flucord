import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/voice_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import 'voice_participant_grid.dart';
import 'voice_room_status.dart';
import '../../domain/voice_connection.dart';
import 'member_avatar.dart';

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
    this.streamViewer,
    this.onWatchStream,
    this.onStopShare,
    this.watchedUserId,
    this.pendingWatchUserId,
    this.cameraFrameFor,
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

  /// The latest picture from a participant's camera, when one is
  /// arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  /// The stage strip, or null for an ordinary voice channel.
  final Widget? stageControls;

  /// The soundboard button, or null where there is nothing to play into.
  final Widget? soundboard;

  /// The Go Live control, or null outside a server voice channel.
  final Widget? goLive;

  /// Somebody else's stream, drawn in place of the participant grid while it
  /// is being watched.
  final Widget? streamViewer;

  /// Opens or closes somebody else's screen share.
  final void Function(String userId)? onWatchStream;

  /// Ends this account's own share, from the tile it is being sent from. Null
  /// while this account is not sharing.
  final VoidCallback? onStopShare;

  /// Whose share is on screen, so the tile offers to leave it.
  final String? watchedUserId;

  /// Whose share has been asked for but is not arriving yet. Kept apart from
  /// [watchedUserId] because an ask Discord never answers must not take the
  /// stage away from the room.
  final String? pendingWatchUserId;

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
                onWatchStream: widget.onWatchStream,
                onStopShare: widget.onStopShare,
                watchedUserId: widget.watchedUserId,
                pendingWatchUserId: widget.pendingWatchUserId,
                goLive: widget.goLive,
                soundboard: widget.soundboard,
                stageControls: widget.stageControls,
                channelName: widget.channelName,
                controller: widget.controller,
                members: widget.members,
                currentMemberId: widget.currentMemberId,
                spaceId: widget.spaceId,
                cameraFrameFor: widget.cameraFrameFor,
              ),
            ),
            _VoiceToolbar(controller: widget.controller, goLive: widget.goLive),
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
          Icon(Icons.podcasts, size: 30, color: context.surfaces.muted),
          const SizedBox(height: 10),
          Text(
            channelName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            seated.isEmpty
                ? 'No one is in the voice channel right now'
                : '${seated.length} in the channel',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
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
            icon: const Icon(Icons.call, size: 16),
            label: const Text('Join voice channel'),
          ),
        ],
      ),
    );
  }
}

class _VoiceStage extends StatelessWidget {
  /// How tall the strip of tiles under a stream on the stage is. One row,
  /// small enough to leave the stream the room.
  static const double _stripHeight = 128;

  const _VoiceStage({
    required this.streamViewer,
    required this.onWatchStream,
    required this.onStopShare,
    required this.watchedUserId,
    required this.pendingWatchUserId,
    required this.goLive,
    required this.soundboard,
    required this.stageControls,
    required this.channelName,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraFrameFor,
  });

  /// The latest picture from a participant's camera, when one is
  /// arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  final String channelName;
  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final Widget? stageControls;
  final Widget? soundboard;
  final Widget? goLive;
  final Widget? streamViewer;
  final void Function(String userId)? onWatchStream;
  final VoidCallback? onStopShare;
  final String? watchedUserId;
  final String? pendingWatchUserId;

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
    final onStage = watchedUserId != null;
    Widget grid({required bool compact}) => VoiceParticipantGrid(
      participants: controller.participants,
      members: members,
      currentMemberId: currentMemberId,
      spaceId: spaceId,
      cameraFrameFor: cameraFrameFor,
      onWatchStream: onWatchStream,
      onStopShare: onStopShare,
      openStreamUserId: watchedUserId ?? pendingWatchUserId,
      compact: compact,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?soundboard,
              const SizedBox(width: 12),
              Text(
                voiceRoomStatusLabel(controller),
                style: TextStyle(
                  color: controller.isTransportReady
                      ? FlucordColors.success
                      : context.surfaces.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // What is wrong, rather than the old fixed sentence: a room that says
        // nothing is indistinguishable from one that is simply quiet.
        if (voiceRoomWarning(controller) case final warning?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    warning,
                    key: const ValueKey('voice-room-warning'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ),
                // Offered here because the alternative was leaving the channel
                // and coming back, which is not an obvious way to ask a client
                // to look for a headset again.
                if (voiceRoomOffersDeviceRetry(controller))
                  TextButton(
                    key: const ValueKey('voice-room-retry-devices'),
                    onPressed: () => unawaited(controller.retryDevices()),
                    child: const Text('Try devices again'),
                  ),
              ],
            ),
          ),
        ?stageControls,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A stream on the stage pushes the grid into a strip rather
              // than off the screen: the tile is where the mark and the
              // control for that stream live, and a stage with no tiles has
              // nowhere to put either.
              if (onStage)
                Expanded(child: streamViewer ?? const SizedBox.shrink()),
              onStage
                  ? SizedBox(height: _stripHeight, child: grid(compact: true))
                  : Expanded(child: grid(compact: false)),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceToolbar extends StatelessWidget {
  const _VoiceToolbar({required this.controller, this.goLive});

  final VoiceController controller;

  /// The Go Live control, which is the room's only share button.
  final Widget? goLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('voice-mute'),
            onPressed: controller.isConnected && !controller.isBusy
                ? controller.toggleMute
                : null,
            tooltip: controller.isMuted ? 'Unmute' : 'Mute',
            style: _controlStyle(
              context,
              foreground: controller.isMuted ? FlucordColors.danger : null,
            ),
            icon: Icon(controller.isMuted ? Icons.mic_off : Icons.mic),
          ),
          // One share control, not two. The room used to carry a local
          // capture button here and a Go Live button in the header, which
          // looked like a choice and was not one: only Go Live puts a picture
          // in the channel.
          if (goLive case final control?) ...[
            const SizedBox(width: 12),
            control,
          ],
          const SizedBox(width: 12),
          IconButton.filled(
            key: const ValueKey('voice-disconnect'),
            onPressed: controller.isConnected && !controller.isBusy
                ? controller.disconnect
                : null,
            tooltip: 'Disconnect',
            style: IconButton.styleFrom(
              backgroundColor: FlucordColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.call_end),
          ),
        ],
      ),
    );
  }

  ButtonStyle _controlStyle(BuildContext context, {Color? foreground}) =>
      IconButton.styleFrom(
        backgroundColor: context.surfaces.raised,
        foregroundColor: foreground ?? Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: context.surfaces.border),
      );
}
