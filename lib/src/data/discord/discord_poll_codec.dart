import '../../domain/chat_models.dart';

abstract final class DiscordPollCodec {
  static Map<String, Object?> request(PendingPoll poll) => {
    'question': {'text': poll.question},
    'answers': [
      for (final answer in poll.answers)
        {
          'poll_media': {'text': answer},
        },
    ],
    'duration': poll.durationHours,
    'allow_multiselect': poll.allowMultiselect,
    'layout_type': 1,
  };
}
