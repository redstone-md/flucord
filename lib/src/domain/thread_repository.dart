import 'chat_models.dart';

final class ArchivedThreadPage {
  ArchivedThreadPage({
    required List<ConversationChannel> threads,
    required this.hasMore,
    this.nextBefore,
  }) : threads = List.unmodifiable(threads);

  final List<ConversationChannel> threads;
  final bool hasMore;
  final DateTime? nextBefore;
}

abstract interface class ArchivedThreadRepository {
  Future<ArchivedThreadPage> loadArchivedThreads(
    String parentChannelId, {
    DateTime? before,
  });
}
