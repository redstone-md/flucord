part of 'message_search.dart';

/// One entry of the response's `messages` array.
///
/// Discord answers with `Message[][]`: every element is a *group* holding the
/// matched message together with the messages around it, which is what lets
/// the results panel show a hit in its conversation instead of alone.
///
/// The group is kept in the order the server sent it and the match is
/// identified by the raw `hit` flag rather than by position. The desktop
/// client simply takes element 0, but R05 records both the position of the hit
/// and whether context precedes or follows it as unestablished — reordering on
/// a guess would move the wrong message under the reader's eye.
final class MessageSearchHitGroup {
  MessageSearchHitGroup({
    required List<ChatMessage> messages,
    required this.hitIndex,
  }) : messages = List.unmodifiable(messages) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'Cannot be empty');
    }
    if (hitIndex < 0 || hitIndex >= messages.length) {
      throw RangeError.index(hitIndex, messages, 'hitIndex');
    }
  }

  final List<ChatMessage> messages;

  /// Where in [messages] the matched message sits.
  final int hitIndex;

  ChatMessage get hit => messages[hitIndex];

  /// Whether this group carries anything beyond the match itself.
  bool get hasContext => messages.length > 1;
}

/// One page of a search, plus everything the envelope carried alongside it.
final class MessageSearchResults {
  MessageSearchResults({
    required int totalResults,
    required List<MessageSearchHitGroup> groups,
    List<Member> authors = const [],
    List<ConversationChannel> channels = const [],
    this.analyticsId,
    this.doingDeepHistoricalIndex = false,
    int documentsIndexed = 0,
  }) : totalResults = totalResults < 0 ? 0 : totalResults,
       documentsIndexed = documentsIndexed < 0 ? 0 : documentsIndexed,
       groups = List.unmodifiable(groups),
       authors = List.unmodifiable(authors),
       channels = List.unmodifiable(channels);

  /// What the server says the whole result set holds.
  ///
  /// Floored at zero: it is a count, and a negative one arriving from the wire
  /// would otherwise flow straight into page arithmetic and produce a pager
  /// with fewer than zero pages.
  final int totalResults;
  final List<MessageSearchHitGroup> groups;

  /// The authors of the hits, mapped from the `author` object on each message
  /// so a result from a channel the account has never opened still has a name
  /// and an avatar.
  final List<Member> authors;

  /// Channels and threads the envelope named, so a hit inside a thread the
  /// workspace has never loaded can still say where it came from.
  final List<ConversationChannel> channels;

  /// Opaque per-request id. Discord echoes it into its search analytics; it is
  /// kept because it is the only handle a support conversation could use, and
  /// it is never sent anywhere by Flucord.
  final String? analyticsId;

  /// The server is still backfilling this guild's index, so the result set is
  /// incomplete even though this request succeeded. Unlike a 202 this is not a
  /// reason to retry — it is a caveat to show next to real results.
  final bool doingDeepHistoricalIndex;
  final int documentsIndexed;

  bool get isEmpty => groups.isEmpty;

  /// The count to show: pagination cannot walk past
  /// [MessageSearchQuery.reachableResults], so a larger total is displayed
  /// capped and flagged rather than promising pages that do not exist.
  int get reachableTotal => totalResults > MessageSearchQuery.reachableResults
      ? MessageSearchQuery.reachableResults
      : totalResults;

  bool get isTotalLimited => totalResults > MessageSearchQuery.reachableResults;

  /// How many pages the pager may offer.
  ///
  /// Derived from [reachableTotal] rather than the raw count, which is what
  /// bounds it: the capped total is exactly
  /// `maxPageIndex + 1` pages of [MessageSearchQuery.pageSize], so a total of
  /// a million cannot produce a pager nobody can walk.
  int get pageCount =>
      (reachableTotal + MessageSearchQuery.pageSize - 1) ~/
      MessageSearchQuery.pageSize;
}

/// How one search attempt ended.
///
/// Indexing is not an error and cancellation is not a failure, so neither is
/// modelled as a thrown exception: a caller that only caught errors would show
/// "search failed" for a server that is merely still building its index.
sealed class MessageSearchOutcome {
  const MessageSearchOutcome();
}

final class MessageSearchCompleted extends MessageSearchOutcome {
  const MessageSearchCompleted(this.results);

  final MessageSearchResults results;
}

/// The server answered `202 Accepted`: it has not finished indexing this
/// corpus and asked to be tried again after [retryAfter].
///
/// As an outcome this means the client's retry budget ran out with the server
/// still indexing. As a progress callback it reports one such answer while the
/// retries are still running.
final class MessageSearchIndexing extends MessageSearchOutcome {
  const MessageSearchIndexing({
    required this.attempts,
    required this.retryAfter,
  });

  /// How many 202 answers have arrived so far.
  final int attempts;

  /// How long the server asked the client to wait before asking again.
  final Duration retryAfter;
}

/// A newer search for the same scope replaced this one before it finished, so
/// its result must not be written over the newer search's state.
final class MessageSearchCancelled extends MessageSearchOutcome {
  const MessageSearchCancelled();
}
