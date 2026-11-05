import 'chat_models.dart';

/// One page of the threads under a channel, or of the posts in a forum,
/// newest activity first, active and archived together.
final class ThreadPage {
  ThreadPage({
    required List<ConversationChannel> threads,
    required this.hasMore,
    List<ChatMessage> firstMessages = const [],
  }) : threads = List.unmodifiable(threads),
       firstMessages = List.unmodifiable(firstMessages);

  final List<ConversationChannel> threads;

  /// The opening message of each forum post that has one, for its preview.
  /// Discord sends these only for forum and media channels.
  final List<ChatMessage> firstMessages;
  final bool hasMore;
}

abstract interface class ThreadListRepository {
  /// Lists the threads under [parentId], skipping the first [offset] of them.
  ///
  /// A non-empty [tagIds] keeps only forum posts that carry at least one of
  /// those tags, as Discord's own forum filter does.
  Future<ThreadPage> loadThreads(
    String parentId, {
    int offset = 0,
    Set<String> tagIds = const {},
  });
}
