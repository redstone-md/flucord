import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'context_menu_target.dart';
import 'member_avatar.dart';
import 'participant_menu.dart';
import 'voice_participant_grid.dart';
import 'voice_room_controls.dart';
import 'voice_room_status.dart';
import 'voice_stream_controls.dart';

/// The call in a DM, drawn as a band above the messages: the connection
/// state, one large avatar per person, and the Room's control row.
///
/// A Stream in the call has no design of its own here. It gets the Room's
/// Stream tile, at the strip's size, after the people.
class DirectCallBand extends StatelessWidget {
  const DirectCallBand({
    required this.channel,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    this.ringing = false,
    this.camera,
    this.goLive,
    this.soundboard,
    this.participantMenu,
    this.streams,
    this.onTapStream,
    super.key,
  });

  final ConversationChannel channel;
  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;

  /// Whether this account has rung the DM and the ring is still out.
  final bool ringing;
  final SelfVideoController? camera;
  final Widget? goLive;

  /// The soundboard button. It hides itself where the account may not use
  /// the soundboard in a call.
  final Widget? soundboard;
  final ParticipantMenu? participantMenu;

  /// The Streams this client has open, and what their tiles offer.
  final VoiceStreamControls? streams;

  /// A Stream tile was clicked.
  final void Function(String userId)? onTapStream;

  /// The people the band shows: the DM's Recipients, anyone else in the
  /// call, then this account.
  List<String> _people(Iterable<String> inCall) => [
    ...channel.recipientIds,
    for (final userId in inCall)
      if (userId != currentMemberId && !channel.recipientIds.contains(userId))
        userId,
    currentMemberId,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _band(context, {
      for (final participant in controller.participants)
        participant.userId: participant,
    }),
  );

  Widget _band(
    BuildContext context,
    Map<String, VoiceParticipant> participants,
  ) {
    // The ringing look holds until a Recipient walks in. A ring that ends
    // unanswered clears [ringing] by itself.
    final calling =
        ringing && !channel.recipientIds.any(participants.containsKey);
    final connected =
        !calling && controller.connectionStatus == VoiceConnectionStatus.ready;
    final streamTiles = VoiceParticipantGrid.tilesOf(
      participants.values,
      currentMemberId: currentMemberId,
      streams: streams,
    ).where((tile) => tile.kind == VoiceTileKind.stream);
    return DecoratedBox(
      key: const ValueKey('call-band'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _CallStatus(
                // Shown once the call is up and answered, and counted from
                // when this account joined, so it includes the ringing.
                joinedAt: connected ? controller.joinedAt : null,
                label: calling
                    ? 'Calling ${channel.name}'
                    : voiceRoomStatusLabel(controller),
                isUp: controller.isTransportReady,
              ),
            ),
          ),
          // One row that scrolls sideways, so a group DM never makes the
          // band taller than the window can give it.
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 40,
                children: [
                  for (final userId in _people(participants.keys))
                    _CallPerson(
                      key: ValueKey('call-band-$userId'),
                      member: voiceMemberOf(members, userId),
                      participant: participants[userId],
                      isSelf: userId == currentMemberId,
                      calling: calling,
                      spaceId: channel.spaceId,
                      menu: participantMenu,
                    ),
                  for (final (:participant, kind: _) in streamTiles)
                    SizedBox(
                      width: VoiceParticipantGrid.stripTileWidth,
                      height: VoiceParticipantGrid.stripHeight,
                      child: VoiceStreamTile(
                        participant: participant,
                        members: members,
                        currentMemberId: currentMemberId,
                        spaceId: channel.spaceId,
                        streams: streams,
                        onTap: onTapStream,
                        size: VoiceParticipantTileSize.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
          VoiceRoomControls(
            controller: controller,
            camera: camera,
            goLive: goLive,
            soundboard: soundboard,
          ),
        ],
      ),
    );
  }
}

/// One person in the band. Their avatar carries one badge, the first of the
/// marks a Room tile shows: the band has room for one, and it must say the
/// same as the tile. Somebody not in the call is dimmed, with two rings
/// while they are being rung.
class _CallPerson extends StatelessWidget {
  const _CallPerson({
    required this.member,
    required this.participant,
    required this.isSelf,
    required this.calling,
    required this.spaceId,
    required this.menu,
    super.key,
  });

  final Member member;

  /// Their place in the call, or null while they are not in it.
  final VoiceParticipant? participant;
  final bool isSelf;

  /// Whether the call is ringing, unanswered.
  final bool calling;
  final String spaceId;
  final ParticipantMenu? menu;

  static const _avatar = 88.0;

  /// The square the avatar and its speaking ring sit in.
  static const _slot = 104.0;

  /// How far the two ringing rings reach past [_slot].
  static const _ringingSpread = [4.0, 12.0];

  ParticipantMark? get _badge => participantMarks(
    participant,
    mutedForYou: menu?.isMutedForYou(member.id) ?? false,
  ).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    // This account is in the call, whether or not the roster says so yet.
    final away = participant == null && !isSelf;
    final caption = switch ((calling, isSelf, away)) {
      (true, true, _) => 'You',
      (true, false, true) => 'Ringing',
      _ => null,
    };
    final avatar = MemberAvatar(
      member: member,
      size: _avatar,
      showPresence: false,
      spaceId: spaceId,
    );
    Widget person(bool hasFocus) => Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        SizedBox.square(
          dimension: _slot,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (away && calling)
                for (final spread in _ringingSpread)
                  Positioned(
                    left: -spread,
                    top: -spread,
                    right: -spread,
                    bottom: -spread,
                    child: _Ring(
                      key: spread == _ringingSpread.first
                          ? const ValueKey('call-band-ringing')
                          : null,
                      color: surfaces.border,
                      width: 1,
                    ),
                  ),
              if (hasFocus)
                _Ring(color: surfaces.focusRing)
              else if (participant?.isSpeaking ?? false)
                _Ring(
                  key: const ValueKey('call-band-speaking'),
                  color: surfaces.success,
                ),
              if (away)
                Opacity(
                  key: const ValueKey('call-band-away'),
                  opacity: 0.5,
                  child: avatar,
                )
              else
                avatar,
              if (_badge case (:final icon, :final label, byServer: _))
                PositionedDirectional(
                  end: 4,
                  bottom: 4,
                  child: Tooltip(
                    message: label,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: surfaces.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: surfaces.surface, width: 2),
                      ),
                      child: FlucordIcon(
                        icon,
                        size: 14,
                        color: FlucordFixedColors.onFill,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Text(
              member.displayNameFor(spaceId),
              style: FlucordTextRole.label.strong.copyWith(
                color: surfaces.text,
              ),
            ),
            if (caption != null)
              Text(
                caption,
                style: FlucordTextRole.caption.style.copyWith(
                  color: surfaces.muted,
                ),
              ),
          ],
        ),
      ],
    );
    final menu = this.menu;
    if (menu == null) return person(false);
    return ContextMenuTarget(
      onOpen: (context, position) =>
          unawaited(menu.open(context, member.id, position: position)),
      builder: (_, hasFocus) => person(hasFocus),
    );
  }
}

/// A circle drawn around an avatar.
class _Ring extends StatelessWidget {
  const _Ring({required this.color, this.width = 2, super.key});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: width),
    ),
    child: const SizedBox.expand(),
  );
}

/// The band's connection state, with how long the call has run once it is
/// up. Its own widget so that only this line redraws each second.
class _CallStatus extends StatefulWidget {
  const _CallStatus({
    required this.joinedAt,
    required this.label,
    required this.isUp,
  });

  /// When this account joined the call, or null while it is not connected.
  final DateTime? joinedAt;

  /// What to say while [joinedAt] is null.
  final String label;
  final bool isUp;

  @override
  State<_CallStatus> createState() => _CallStatusState();
}

class _CallStatusState extends State<_CallStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(covariant _CallStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTick() {
    if (widget.joinedAt == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final joinedAt = widget.joinedAt;
    return VoiceSignalLine(
      isUp: widget.isUp,
      text: joinedAt == null
          ? TextSpan(text: widget.label)
          : TextSpan(
              children: [
                TextSpan(
                  text: 'Connected',
                  style: FlucordTextRole.caption.strong.copyWith(
                    color: context.surfaces.success,
                  ),
                ),
                TextSpan(
                  text: ' · ${_callLength(clock.now().difference(joinedAt))}',
                ),
              ],
            ),
    );
  }
}

/// A call's length as a clock reads it: "4:05", or "1:02:03" past an hour.
String _callLength(Duration length) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final minutes = length.inMinutes;
  final seconds = twoDigits(length.inSeconds % 60);
  if (minutes < 60) return '$minutes:$seconds';
  return '${length.inHours}:${twoDigits(minutes % 60)}:$seconds';
}
