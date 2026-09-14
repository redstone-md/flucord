part of 'discord_mapper.dart';

extension _DiscordPollMapper on DiscordMapper {
  MessagePoll? _mapPoll(Object? value) {
    if (value is! Map) return null;
    final payload = value.cast<String, Object?>();
    final rawQuestion = payload['question'];
    final question = rawQuestion is Map ? rawQuestion['text'] as String? : null;
    if (question == null) return null;
    final results = payload['results'];
    final resultMap = results is Map
        ? results.cast<String, Object?>()
        : const <String, Object?>{};
    final counts = <int, Map<String, Object?>>{};
    for (final raw in resultMap['answer_counts'] as List? ?? const []) {
      if (raw is! Map) continue;
      final count = raw.cast<String, Object?>();
      final id = count['id'] as int?;
      if (id != null) counts[id] = count;
    }
    final answers = <PollAnswer>[];
    for (final raw in payload['answers'] as List? ?? const []) {
      if (raw is! Map) continue;
      final answer = raw.cast<String, Object?>();
      final id = answer['answer_id'] as int?;
      final media = answer['poll_media'];
      if (id == null || media is! Map) continue;
      final mediaMap = media.cast<String, Object?>();
      final emoji = mediaMap['emoji'];
      final emojiMap = emoji is Map
          ? emoji.cast<String, Object?>()
          : const <String, Object?>{};
      final count = counts[id];
      answers.add(
        PollAnswer(
          id: id,
          text: mediaMap['text'] as String? ?? '',
          count: count?['count'] as int? ?? 0,
          votedByCurrentUser: count?['me_voted'] as bool? ?? false,
          emojiId: emojiMap['id'] as String?,
          emojiName: emojiMap['name'] as String?,
          emojiAnimated: emojiMap['animated'] as bool? ?? false,
        ),
      );
    }
    final rawExpiry = payload['expiry'] as String?;
    return MessagePoll(
      question: question,
      answers: answers,
      expiry: rawExpiry == null
          ? null
          : DateTime.tryParse(rawExpiry)?.toLocal(),
      allowMultiselect: payload['allow_multiselect'] as bool? ?? false,
      isFinalized: resultMap['is_finalized'] as bool? ?? false,
    );
  }
}
