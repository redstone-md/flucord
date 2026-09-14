import '../domain/discord_social_activity.dart';

abstract final class DiscordSocialActivityMapper {
  static DiscordSocialActivityInviteEvent event(Object? payload) {
    final map = _map(payload, 'Activity invite event');
    return DiscordSocialActivityInviteEvent(
      invite: invite(map['invite']),
      updated: map['type'] == 'updated',
    );
  }

  static DiscordSocialActivityInvite invite(Object? payload) {
    final map = _map(payload, 'Activity invite');
    return DiscordSocialActivityInvite(
      applicationId: _id(map['application_id']),
      parentApplicationId: _id(map['parent_application_id']),
      channelId: _id(map['channel_id']),
      messageId: _id(map['message_id']),
      senderId: _id(map['sender_id']),
      partyId: _text(map['party_id']),
      sessionId: _text(map['session_id']),
      type: switch (map['invite_type']) {
        'join' => DiscordSocialActivityInviteType.join,
        'join_request' => DiscordSocialActivityInviteType.joinRequest,
        _ => DiscordSocialActivityInviteType.unknown,
      },
      isValid: map['is_valid'] == true,
    );
  }

  static Map<String, Object> encode(DiscordSocialActivityInvite invite) => {
    'application_id': invite.applicationId,
    'parent_application_id': invite.parentApplicationId,
    'channel_id': invite.channelId,
    'message_id': invite.messageId,
    'sender_id': invite.senderId,
    'party_id': invite.partyId,
    'session_id': invite.sessionId,
    'invite_type': switch (invite.type) {
      DiscordSocialActivityInviteType.join => 'join',
      DiscordSocialActivityInviteType.joinRequest => 'join_request',
      DiscordSocialActivityInviteType.unknown => 'unknown',
    },
    'is_valid': invite.isValid,
  };

  static DiscordSocialActivitySession session(Object? payload) {
    final map = _map(payload, 'Activity session');
    return DiscordSocialActivitySession(lobbyId: _id(map['lobby_id']));
  }

  static Map<Object?, Object?> _map(Object? value, String label) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$label payload must be a map.');
    }
    return value;
  }

  static String _id(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => number.toString(),
    _ => '',
  };

  static String _text(Object? value) => value is String ? value.trim() : '';
}
