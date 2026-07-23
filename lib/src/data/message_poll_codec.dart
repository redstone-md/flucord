import 'dart:convert';

import '../domain/chat_models.dart';

abstract final class MessagePollCodec {
  static String? encode(MessagePoll? poll) => poll == null
      ? null
      : jsonEncode({
          'question': poll.question,
          'expiry': poll.expiry?.toUtc().toIso8601String(),
          'allow_multiselect': poll.allowMultiselect,
          'is_finalized': poll.isFinalized,
          'answers': [
            for (final answer in poll.answers)
              {
                'id': answer.id,
                'text': answer.text,
                'count': answer.count,
                'emoji_id': answer.emojiId,
                'emoji_name': answer.emojiName,
                'emoji_animated': answer.emojiAnimated,
                'me_voted': answer.votedByCurrentUser,
              },
          ],
        });

  static MessagePoll? decode(String? source) {
    if (source == null) return null;
    final raw = jsonDecode(source) as Map;
    final expiry = raw['expiry'] as String?;
    return MessagePoll(
      question: raw['question'] as String,
      expiry: expiry == null ? null : DateTime.parse(expiry).toLocal(),
      allowMultiselect: raw['allow_multiselect'] as bool,
      isFinalized: raw['is_finalized'] as bool,
      answers: (raw['answers'] as List)
          .whereType<Map>()
          .map(
            (answer) => PollAnswer(
              id: answer['id'] as int,
              text: answer['text'] as String,
              count: answer['count'] as int,
              emojiId: answer['emoji_id'] as String?,
              emojiName: answer['emoji_name'] as String?,
              emojiAnimated: answer['emoji_animated'] as bool,
              votedByCurrentUser: answer['me_voted'] as bool,
            ),
          )
          .toList(growable: false),
    );
  }
}
