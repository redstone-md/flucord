import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import 'camera_picture.dart';
import 'member_avatar.dart';

class VoiceParticipantGrid extends StatelessWidget {
  const VoiceParticipantGrid({
    required this.participants,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraFrameFor,
    this.onWatchStream,
    this.watchedUserId,
    super.key,
  });

  final List<VoiceParticipant> participants;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;

  /// The latest picture from a participant's camera, when one is arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  /// Opens somebody's screen share, or closes the one being watched. Null on a
  /// surface that cannot watch — a build with no decoder, or a call.
  final void Function(String userId)? onWatchStream;

  /// Whose share is on screen, so the tile offers to leave rather than join.
  final String? watchedUserId;

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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
          onWatchStream: onWatchStream,
          isWatched: participant.userId == watchedUserId,
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
    this.onWatchStream,
    this.isWatched = false,
  });

  final DecodedVideoFrame? cameraFrame;
  final VoiceParticipant participant;
  final Member member;
  final bool isCurrentUser;
  final String spaceId;
  final void Function(String userId)? onWatchStream;
  final bool isWatched;

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
            if (cameraFrame case final DecodedVideoFrame frame)
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
                    size: 64,
                    showPresence: false,
                    spaceId: spaceId,
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                  // A share nobody can open is only an icon. Discord puts a
                  // button on the tile, and so does this: the stream is a
                  // separate connection that is only dialled when asked for.
                  if (participant.isStreaming)
                    if (onWatchStream case final watch? when !isCurrentUser)
                      IconButton(
                        key: ValueKey('voice-watch-${participant.userId}'),
                        tooltip: isWatched
                            ? 'Stop watching'
                            : 'Watch ${member.displayName}',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        onPressed: () => watch(participant.userId),
                        icon: Icon(
                          isWatched
                              ? Icons.stop_screen_share
                              : Icons.screen_share_outlined,
                          size: 15,
                          color: isWatched ? FlucordColors.danger : null,
                        ),
                      )
                    else
                      const _StateIcon(
                        icon: Icons.screen_share_outlined,
                        label: 'Streaming',
                      ),
                  if (participant.isDeafened)
                    const _StateIcon(
                      icon: Icons.headset_off_outlined,
                      label: 'Deafened',
                    )
                  else if (participant.isMuted)
                    const _StateIcon(
                      icon: Icons.mic_off_outlined,
                      label: 'Muted',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
