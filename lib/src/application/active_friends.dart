import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/voice_connection.dart';

/// A friend who is doing something right now: playing, listening, watching,
/// or sitting in a voice channel.
@immutable
final class ActiveFriend {
  const ActiveFriend({required this.person, this.room});

  final Member person;

  /// The voice channel they sit in, or null when they are in none this
  /// workspace knows.
  final ActiveFriendRoom? room;

  /// What they are doing, moods left out.
  List<UserActivity> get doing => person.presenceDetail?.doing ?? const [];
}

/// The guild voice channel a friend sits in, with everybody seated there.
@immutable
final class ActiveFriendRoom {
  const ActiveFriendRoom({
    required this.channel,
    required this.space,
    required this.people,
  });

  final ConversationChannel channel;
  final CommunitySpace space;

  /// Everybody in the channel the workspace has a member for, the friend
  /// included.
  final List<Member> people;
}

/// The friends among [friendIds] who are doing something or sit in a voice
/// channel, in the order given.
List<ActiveFriend> activeFriends(
  Iterable<String> friendIds, {
  required ChatWorkspace workspace,
  required Map<String, List<VoiceParticipantStateEvent>> seatedByChannel,
}) {
  final seatOf = {
    for (final seats in seatedByChannel.values)
      for (final seat in seats) seat.userId: seat,
  };
  return [
    for (final id in friendIds)
      if (workspace.memberOrNull(id) case final person?)
        ActiveFriend(
          person: person,
          room: _roomOf(seatOf[id], workspace, seatedByChannel),
        ),
  ].where((friend) => friend.room != null || friend.doing.isNotEmpty).toList();
}

ActiveFriendRoom? _roomOf(
  VoiceParticipantStateEvent? seat,
  ChatWorkspace workspace,
  Map<String, List<VoiceParticipantStateEvent>> seatedByChannel,
) {
  final channelId = seat?.channelId;
  final guildId = seat?.guildId;
  if (channelId == null || guildId == null) return null;
  final channel = workspace.channelOrNull(channelId);
  final space = workspace.spaceOrNull(guildId);
  if (channel == null || space == null) return null;
  return ActiveFriendRoom(
    channel: channel,
    space: space,
    people: [
      for (final other in seatedByChannel[channelId] ?? const [])
        ?workspace.memberOrNull(other.userId),
    ],
  );
}
