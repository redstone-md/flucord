/// One stretch of a channel's history, as Discord summarised it.
///
/// Discord generates these server-side and pushes them; a client cannot ask
/// for one, which is why this is a store fed by a dispatch rather than a
/// repository with a load method.
final class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.channelId,
    this.topic = '',
    this.summary = '',
    this.participantIds = const [],
    this.startMessageId = '',
    this.endMessageId = '',
    this.messageCount = 0,
  });

  final String id;
  final String channelId;

  /// A few words naming what was discussed.
  final String topic;

  /// The sentence or two Discord wrote about it.
  final String summary;

  /// Who took part, in the order Discord listed them.
  final List<String> participantIds;

  /// The first and last message the summary covers. Jumping to a summary
  /// means jumping here.
  final String startMessageId;
  final String endMessageId;

  final int messageCount;

  bool get isEmpty => topic.isEmpty && summary.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.id == id &&
      other.channelId == channelId &&
      other.topic == topic &&
      other.summary == summary &&
      other.startMessageId == startMessageId &&
      other.endMessageId == endMessageId &&
      other.messageCount == messageCount;

  @override
  int get hashCode => Object.hash(
    id,
    channelId,
    topic,
    summary,
    startMessageId,
    endMessageId,
    messageCount,
  );
}

/// The summaries a session has been told about.
abstract interface class ConversationSummaryRepository {
  /// Summaries for [channelId], newest first.
  List<ConversationSummary> summariesFor(String channelId);

  /// Fires with a channel id whenever its summaries change.
  Stream<String> get updates;
}
