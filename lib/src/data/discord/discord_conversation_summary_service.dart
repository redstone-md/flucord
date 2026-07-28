import 'dart:async';

import '../../domain/conversation_summary.dart';
import '../../domain/discord_snowflake.dart';

/// Conversation summaries, as `CONVERSATION_SUMMARY_UPDATE` delivers them.
///
/// Availability is an experiment Discord decides per account, so a session
/// that never receives one is not a failure: the surface simply has nothing to
/// show, which is why nothing here asks for a summary or reports its absence
/// as an error.
final class DiscordConversationSummaryService
    implements ConversationSummaryRepository {
  /// How many summaries a channel keeps, matching what the desktop client
  /// retains: past this the oldest are dropped rather than growing without
  /// bound on a busy channel.
  static const retainedPerChannel = 75;

  final StreamController<String> _updates = StreamController.broadcast();
  final Map<String, List<ConversationSummary>> _byChannel = {};

  @override
  List<ConversationSummary> summariesFor(String channelId) =>
      List.unmodifiable(_byChannel[channelId] ?? const []);

  @override
  Stream<String> get updates => _updates.stream;

  /// Folds a dispatch in, returning the channel it changed or `null`.
  String? accept(String eventName, Map<String, Object?> data) {
    if (eventName != 'CONVERSATION_SUMMARY_UPDATE') return null;
    final channelId = data['channel_id'];
    if (channelId is! String || channelId.isEmpty) return null;
    final arriving = [
      for (final raw in _objects(data['summaries']))
        ?readSummary(raw, channelId),
    ];
    if (arriving.isEmpty) return null;

    // A dispatch carries the summaries that changed, not the whole set, so it
    // merges: an id already held is replaced rather than duplicated.
    final byId = <String, ConversationSummary>{
      for (final summary
          in _byChannel[channelId] ?? const <ConversationSummary>[])
        summary.id: summary,
    };
    for (final summary in arriving) {
      byId[summary.id] = summary;
    }
    final merged = byId.values.toList()
      // Newest first, ordered by the message each summary starts at rather
      // than by arrival: a late dispatch about an old stretch belongs where
      // that stretch is, not at the top.
      ..sort((a, b) => _startsAfter(b, a));
    _byChannel[channelId] = merged.length > retainedPerChannel
        ? merged.sublist(0, retainedPerChannel)
        : merged;
    if (!_updates.isClosed) _updates.add(channelId);
    return channelId;
  }

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  /// Maps one summary, skipping anything with no id or nothing to say.
  static ConversationSummary? readSummary(
    Map<String, Object?> payload,
    String channelId,
  ) {
    final id = payload['id'];
    if (id is! String || id.isEmpty) return null;
    final summary = ConversationSummary(
      id: id,
      channelId: channelId,
      topic: _text(payload['topic']),
      summary: _text(payload['summ_short']),
      // Discord repeats a participant when they spoke in several stretches of
      // the same summary; the list is what a surface names, so it is deduped.
      participantIds: {..._strings(payload['people'])}.toList(growable: false),
      startMessageId: _text(payload['start_id']),
      endMessageId: _text(payload['end_id']),
      messageCount: payload['count'] is int ? payload['count']! as int : 0,
    );
    // An empty summary is one Discord is still working on. Showing a blank
    // card would be worse than showing nothing.
    return summary.isEmpty ? null : summary;
  }

  /// Orders by the snowflake the stretch starts at, which is a time even
  /// though it is an id; a summary with none falls back to its own id.
  static int _startsAfter(ConversationSummary a, ConversationSummary b) {
    if (a.startMessageId.isEmpty || b.startMessageId.isEmpty) {
      return DiscordSnowflake.compare(a.id, b.id);
    }
    return DiscordSnowflake.compare(a.startMessageId, b.startMessageId);
  }

  static String _text(Object? value) => value is String ? value : '';

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
