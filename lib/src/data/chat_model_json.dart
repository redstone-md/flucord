import 'dart:convert';

import '../domain/chat_models.dart';

final class ChatModelJson {
  const ChatModelJson._();

  static String attachments(List<MessageAttachment> values) => jsonEncode([
    for (final value in values)
      {
        'id': value.id,
        'filename': value.fileName,
        'url': value.url,
        'size': value.size,
        'content_type': value.contentType,
        'width': value.width,
        'height': value.height,
      },
  ]);

  static List<MessageAttachment> attachmentsFrom(String source) =>
      (jsonDecode(source) as List)
          .whereType<Map>()
          .map(
            (raw) => MessageAttachment(
              id: raw['id'] as String,
              fileName: raw['filename'] as String,
              url: raw['url'] as String,
              size: raw['size'] as int,
              contentType: raw['content_type'] as String?,
              width: raw['width'] as int?,
              height: raw['height'] as int?,
            ),
          )
          .toList(growable: false);

  static String? reply(MessageReply? value) => value == null
      ? null
      : jsonEncode({
          'message_id': value.messageId,
          'author_id': value.authorId,
          'body': value.body,
        });

  static MessageReply? replyFrom(String? source) {
    if (source == null) return null;
    final raw = jsonDecode(source) as Map;
    return MessageReply(
      messageId: raw['message_id'] as String,
      authorId: raw['author_id'] as String,
      body: raw['body'] as String,
    );
  }

  static String reactions(List<MessageReaction> values) => jsonEncode([
    for (final value in values)
      {
        'name': value.emojiName,
        'id': value.emojiId,
        'count': value.count,
        'animated': value.animated,
        'me': value.reactedByCurrentUser,
      },
  ]);

  static List<MessageReaction> reactionsFrom(String source) =>
      (jsonDecode(source) as List)
          .whereType<Map>()
          .map(
            (raw) => MessageReaction(
              emojiName: raw['name'] as String,
              emojiId: raw['id'] as String?,
              count: raw['count'] as int,
              animated: raw['animated'] as bool,
              reactedByCurrentUser: raw['me'] as bool,
            ),
          )
          .toList(growable: false);
}
