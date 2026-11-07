import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import '../domain/client_sounds.dart';
import '../domain/voice_connection.dart';
import 'voice_controller.dart';

/// What the voice sounds are decided from: the room as this account sees it
/// at one moment.
@immutable
final class VoiceSoundSnapshot {
  const VoiceSoundSnapshot({
    this.channelId,
    this.connected = false,
    this.isStage = false,
    this.muted = false,
    this.deafened = false,
    this.others = const {},
    this.streamers = const {},
    this.followed = const {},
    this.selfSeatedIn,
  });

  static const idle = VoiceSoundSnapshot();

  /// The room this account is in, or joining.
  final String? channelId;

  /// Whether the connection to [channelId] is up.
  final bool connected;
  final bool isStage;
  final bool muted;
  final bool deafened;

  /// Everybody else seated in the room.
  final Set<String> others;

  /// Who in the room is streaming, this account included.
  final Set<String> streamers;

  /// The streamers whose Stream ending this account hears: its own, and
  /// the ones it watches.
  final Set<String> followed;

  /// The channel the server seats this account in, which differs from
  /// [channelId] when somebody else moved it.
  final String? selfSeatedIn;

  VoiceSoundSnapshot copyWith({
    String? channelId,
    bool? connected,
    bool? isStage,
    bool? muted,
    bool? deafened,
    Set<String>? others,
    Set<String>? streamers,
    Set<String>? followed,
    String? selfSeatedIn,
  }) => VoiceSoundSnapshot(
    channelId: channelId ?? this.channelId,
    connected: connected ?? this.connected,
    isStage: isStage ?? this.isStage,
    muted: muted ?? this.muted,
    deafened: deafened ?? this.deafened,
    others: others ?? this.others,
    streamers: streamers ?? this.streamers,
    followed: followed ?? this.followed,
    selfSeatedIn: selfSeatedIn ?? this.selfSeatedIn,
  );
}

/// Join and leave sounds stop past this many people, as in Discord.
const _crowd = 25;

/// The one sound the change from [before] to [after] makes, by Discord's
/// rules, or null. The account's own connection comes first, then a move,
/// deafen, mute, Streams, and last the others coming and going.
///
/// Others are heard coming and going only once the account's own seat was
/// already in the room, so the people there on entry make no sound, even
/// when the roster arrives after the connection.
ClientSound? voiceSoundBetween(
  VoiceSoundSnapshot before,
  VoiceSoundSnapshot after,
) {
  final joined =
      after.connected &&
      (!before.connected || before.channelId != after.channelId);
  // Going to the channel somebody already moved the account to follows a
  // move, whose sound has played.
  final followedMove =
      before.connected && before.selfSeatedIn == after.channelId;
  if (joined) {
    return after.isStage || followedMove ? null : ClientSound.userJoin;
  }
  if (before.connected && !after.connected) {
    return before.isStage ? null : ClientSound.disconnect;
  }
  final seat = after.selfSeatedIn;
  if (after.connected &&
      seat != null &&
      seat != after.channelId &&
      seat != before.selfSeatedIn) {
    return ClientSound.userMoved;
  }
  if (before.deafened != after.deafened) {
    return after.deafened ? ClientSound.deafen : ClientSound.undeafen;
  }
  if (before.muted != after.muted) {
    return after.muted ? ClientSound.mute : ClientSound.unmute;
  }
  if (!after.connected || after.isStage) return null;
  if (after.streamers.difference(before.streamers).isNotEmpty) {
    return ClientSound.streamStarted;
  }
  final ended = before.streamers.difference(after.streamers);
  if (ended.any(before.followed.contains)) return ClientSound.streamEnded;
  if (before.others.length > _crowd || before.selfSeatedIn != after.channelId) {
    return null;
  }
  if (after.others.difference(before.others).isNotEmpty) {
    return ClientSound.userJoin;
  }
  if (before.others.difference(after.others).isNotEmpty) {
    return ClientSound.userLeave;
  }
  return null;
}

/// Plays the voice sounds as the room changes: this account joining,
/// leaving, being moved, muting and deafening, and the others in the room
/// coming, going and streaming.
final class VoiceSoundCues {
  VoiceSoundCues({
    required Listenable changes,
    required VoiceSoundSnapshot Function() read,
    required ClientSoundPlayer sounds,
  }) : _changes = changes,
       _read = read,
       _sounds = sounds,
       _last = read() {
    _changes.addListener(_changed);
  }

  /// Reads the room off the voice controller.
  factory VoiceSoundCues.forRoom({
    required VoiceController voice,
    required ClientSoundPlayer sounds,

    /// Also notifies when this account starts or stops watching a Stream.
    required Listenable streams,
    required String? Function() selfUserId,
    required bool Function(String channelId) isStage,
    required bool Function(String userId) watches,
  }) => VoiceSoundCues(
    changes: Listenable.merge([voice, streams]),
    sounds: sounds,
    read: () => _readRoom(
      voice,
      selfUserId: selfUserId(),
      isStage: isStage,
      watches: watches,
    ),
  );

  final Listenable _changes;
  final VoiceSoundSnapshot Function() _read;
  final ClientSoundPlayer _sounds;
  VoiceSoundSnapshot _last;

  void _changed() {
    final next = _read();
    final sound = voiceSoundBetween(_last, next);
    _last = next;
    if (sound != null) _sounds.play(sound);
  }

  void dispose() => _changes.removeListener(_changed);
}

VoiceSoundSnapshot _readRoom(
  VoiceController voice, {
  required String? selfUserId,
  required bool Function(String channelId) isStage,
  required bool Function(String userId) watches,
}) {
  final channelId = voice.connectedChannelId;
  // Mute and deafen are heard outside a room too, as in Discord.
  if (channelId == null) {
    return VoiceSoundSnapshot(muted: voice.isMuted, deafened: voice.isDeafened);
  }
  final seatedByChannel = voice.seatedByChannel;
  final seated = seatedByChannel[channelId] ?? const [];
  final streamers = {
    for (final state in seated)
      if (state.isStreaming) state.userId,
  };
  final status = voice.connectionStatus;
  return VoiceSoundSnapshot(
    channelId: channelId,
    connected:
        status == VoiceConnectionStatus.ready ||
        status == VoiceConnectionStatus.reconnecting,
    isStage: isStage(channelId),
    muted: voice.isMuted,
    deafened: voice.isDeafened,
    others: {
      for (final state in seated)
        if (state.userId != selfUserId) state.userId,
    },
    streamers: streamers,
    followed: {
      for (final userId in streamers)
        if (userId == selfUserId || watches(userId)) userId,
    },
    selfSeatedIn: selfUserId == null
        ? null
        : seatedByChannel.entries
              .firstWhereOrNull(
                (entry) => entry.value.any((s) => s.userId == selfUserId),
              )
              ?.key,
  );
}
