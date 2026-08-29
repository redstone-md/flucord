import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import 'camera_picture.dart';
import 'member_avatar.dart';
import 'voice_stream_controls.dart';

class VoiceParticipantGrid extends StatelessWidget {
  const VoiceParticipantGrid({
    required this.participants,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraFrameFor,
    this.streams,
    this.compact = false,
    super.key,
  });

  final List<VoiceParticipant> participants;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;

  /// The latest picture from a participant's camera, when one is arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  /// The streams this client has open, and the controls a tile offers for
  /// them. Null where the room was drawn without a stream plane at all.
  final VoiceStreamControls? streams;

  /// Whether the grid is a strip under a stream on the stage rather than the
  /// whole room. Same tiles, smaller, reading left to right.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Center(
        key: const ValueKey('voice-participants-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headset_mic_outlined,
              size: 32,
              color: context.surfaces.muted,
            ),
            const SizedBox(height: 10),
            const Text(
              'Waiting for participants',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    final memberById = {for (final member in members) member.id: member};
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
        return _ParticipantTile(
          cameraFrame: cameraFrameFor?.call(participant.userId),
          participant: participant,
          member:
              memberById[participant.userId] ??
              _unknownMember(participant.userId),
          isCurrentUser: participant.userId == currentMemberId,
          spaceId: spaceId,
          streams: streams,
          compact: compact,
        );
      },
    );
  }

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
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.member,
    required this.isCurrentUser,
    required this.spaceId,
    this.cameraFrame,
    this.streams,
    this.compact = false,
  });

  final DecodedVideoFrame? cameraFrame;
  final VoiceParticipant participant;
  final Member member;
  final bool isCurrentUser;
  final String spaceId;
  final VoiceStreamControls? streams;
  final bool compact;

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

  /// What is wrong with the participant's microphone, if anything.
  List<Widget> get _stateIcons => [
    if (participant.isDeafened)
      const _StateIcon(icon: Icons.headset_off_outlined, label: 'Deafened')
    else if (participant.isMuted)
      const _StateIcon(icon: Icons.mic_off_outlined, label: 'Muted'),
  ];

  @override
  Widget build(BuildContext context) {
    final borderColor = participant.isSpeaking
        ? FlucordColors.success
        : context.surfaces.border;
    return Semantics(
      selected: participant.isSpeaking,
      label: '${member.displayName}, voice participant',
      child: DecoratedBox(
        key: ValueKey('voice-participant-${participant.userId}'),
        decoration: BoxDecoration(
          color: context.surfaces.inset,
          border: Border.all(
            color: borderColor,
            width: participant.isSpeaking ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            if (cameraFrame case final DecodedVideoFrame frame
                when frame.hasPicture)
              Positioned.fill(
                key: ValueKey('voice-camera-${participant.userId}'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CameraPicture(frame: frame),
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
                    size: compact ? 36 : 64,
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
                child: _StreamCard(
                  userId: participant.userId,
                  name: member.displayName,
                  stateIcons: _stateIcons,
                  isOpen: isOpen,
                  onWatch: isCurrentUser ? null : streams?.onWatch,
                  onStopShare: isCurrentUser ? streams?.onStopShare : null,
                ),
              )
            else
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Row(
                  children: [
                    Expanded(child: _TileName(member.displayName)),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Text(
                        'You',
                        style: TextStyle(
                          color: context.surfaces.muted,
                          fontSize: 10,
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
    this.onWatch,
    this.onStopShare,
  });

  final String userId;
  final String name;
  final List<Widget> stateIcons;
  final bool isOpen;

  /// Opens this participant's stream, or closes it once it is open. Null where
  /// the card has nothing to open one with.
  final void Function(String userId)? onWatch;

  /// Ends this account's own share, and the reason its tile has a card.
  final VoidCallback? onStopShare;

  @override
  Widget build(BuildContext context) {
    final accent = FlucordColors.danger;
    return DecoratedBox(
      key: ValueKey('voice-stream-card-$userId'),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        border: Border.all(color: isOpen ? accent : context.surfaces.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The grid gives way to the stage the moment pictures arrive, so
            // the mark is only ever seen for the ask behind them.
            if (isOpen)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv, size: 12, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      'On stage',
                      key: ValueKey('voice-on-stage-$userId'),
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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

  Widget _control(BuildContext context) {
    if (onStopShare case final stop?) {
      return _button(
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
        style: TextStyle(color: context.surfaces.muted, fontSize: 10),
      ),
      final watch => _button(
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

  Widget _button({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: danger ? FlucordColors.danger : null,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Tooltip(
        message: label,
        child: Icon(icon, size: 15, color: FlucordColors.danger),
      ),
    );
  }
}
