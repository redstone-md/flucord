import '../domain/discord_social_call.dart';

abstract final class DiscordSocialCallMapper {
  static DiscordSocialCallState state(Object? payload) {
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('Activity call payload must be a map.');
    }
    final participants = payload['participant_user_ids'];
    final speaking = payload['speaking_user_ids'];
    final locallyMuted = payload['locally_muted_user_ids'];
    if (participants is! List<Object?> ||
        speaking is! List<Object?> ||
        locallyMuted is! List<Object?> ||
        payload['self_muted'] is! bool ||
        payload['self_deafened'] is! bool) {
      throw const FormatException('Activity call payload is incomplete.');
    }
    try {
      return DiscordSocialCallState(
        lobbyId: _identifier(payload['lobby_id']),
        currentUserId: _identifier(payload['current_user_id']),
        status: switch (payload['status']) {
          'disconnected' => DiscordSocialCallStatus.disconnected,
          'joining' => DiscordSocialCallStatus.joining,
          'connecting' => DiscordSocialCallStatus.connecting,
          'signaling_connected' => DiscordSocialCallStatus.signalingConnected,
          'connected' => DiscordSocialCallStatus.connected,
          'reconnecting' => DiscordSocialCallStatus.reconnecting,
          'disconnecting' => DiscordSocialCallStatus.disconnecting,
          _ => DiscordSocialCallStatus.unknown,
        },
        participantUserIds: participants.map(_identifier),
        speakingUserIds: speaking.map(_identifier),
        locallyMutedUserIds: locallyMuted.map(_identifier),
        selfMuted: payload['self_muted']! as bool,
        selfDeafened: payload['self_deafened']! as bool,
      );
    } on ArgumentError {
      throw const FormatException('Activity call identifiers are invalid.');
    }
  }

  static String _identifier(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => number.toString(),
    _ => '',
  };
}
