import '../domain/discord_relationship.dart';
import '../domain/discord_social_dm.dart';

abstract final class DiscordSocialDmMapper {
  static List<DiscordSocialDmConversation> conversations(Object? payload) {
    if (payload is! List<Object?>) {
      throw const FormatException('DM conversations payload must be a list.');
    }
    return List.unmodifiable(payload.map(_conversation));
  }

  static List<DiscordSocialDmMessage> messages(Object? payload) {
    if (payload is! List<Object?>) {
      throw const FormatException('DM messages payload must be a list.');
    }
    return List.unmodifiable(payload.map(message));
  }

  static DiscordSocialDmMessage message(Object? payload) {
    final map = _map(payload, 'DM message');
    final sentAt = _timestamp(map['sent_timestamp']);
    final editedAt = _timestamp(map['edited_timestamp'], optional: true);
    return DiscordSocialDmMessage(
      id: _id(map['id']),
      conversationUserId: _id(map['conversation_user_id']),
      authorId: _id(map['author_id'], optional: true),
      recipientId: _id(map['recipient_id'], optional: true),
      authorDisplayName: _text(map['author_display_name']) ?? 'Unknown user',
      content: map['content'] is String ? map['content']! as String : '',
      sentAt: sentAt!,
      editedAt: editedAt,
      authoredByCurrentUser: map['authored_by_current_user'] == true,
    );
  }

  static DiscordSocialDmEvent event(String method, Object? payload) {
    if (method == 'socialMessageDeleted') {
      final map = _map(payload, 'DM deletion');
      return DiscordSocialDmEvent.deleted(_id(map['message_id']));
    }
    final map = _map(payload, 'DM event');
    final type = switch (map['type']) {
      'created' => DiscordSocialDmEventType.created,
      'updated' => DiscordSocialDmEventType.updated,
      _ => throw const FormatException('Unknown DM event type.'),
    };
    return DiscordSocialDmEvent.changed(type, message(map['message']));
  }

  static DiscordSocialDmConversation _conversation(Object? payload) {
    final map = _map(payload, 'DM conversation');
    final userId = _id(map['user_id']);
    return DiscordSocialDmConversation(
      user: DiscordRelationshipUser(
        id: userId,
        displayName: _text(map['display_name']) ?? userId,
        username: _text(map['username']),
        status: _presence(map['status']),
        isProvisional: map['is_provisional'] == true,
      ),
      lastMessageId: _id(map['last_message_id']),
    );
  }

  static Map<Object?, Object?> _map(Object? value, String label) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$label payload must be a map.');
    }
    return value;
  }

  static String _id(Object? value, {bool optional = false}) {
    final result = switch (value) {
      final String text => text.trim(),
      final int number => number.toString(),
      _ => '',
    };
    if (!optional && result.isEmpty) {
      throw const FormatException('Required DM identifier is missing.');
    }
    return result;
  }

  static String? _text(Object? value) {
    final result = value is String ? value.trim() : '';
    return result.isEmpty ? null : result;
  }

  static DateTime? _timestamp(Object? value, {bool optional = false}) {
    final milliseconds = switch (value) {
      final int number => number,
      final String text => int.tryParse(text),
      _ => null,
    };
    if (milliseconds == null || milliseconds <= 0) {
      if (optional) return null;
      throw const FormatException('Required DM timestamp is missing.');
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static DiscordPresenceStatus _presence(Object? value) => switch (value) {
    'online' => DiscordPresenceStatus.online,
    'idle' => DiscordPresenceStatus.idle,
    'dnd' => DiscordPresenceStatus.doNotDisturb,
    'offline' => DiscordPresenceStatus.offline,
    _ => DiscordPresenceStatus.unknown,
  };
}
