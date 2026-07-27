import 'message_search.dart';

/// Reports one `202 Accepted` while the search is still being retried.
typedef MessageSearchIndexingCallback =
    void Function(MessageSearchIndexing status);

/// Server-side message search, as a capability a transport either has or does
/// not.
///
/// Only a session that can reach the account's own search routes can answer
/// this. A bot token cannot: the routes are user-scoped, and a bot asking for
/// them is a rejection, not an empty result. Stating the capability on the
/// contract — rather than letting the search surface guess from the
/// repository's runtime type — is what lets those transports say honestly that
/// they have no search, and what will let a future one gain it without editing
/// every caller.
abstract interface class MessageSearchRepository {
  /// Runs [request], polling through the server's "still indexing" answers.
  ///
  /// [onIndexing] fires once per 202 so the surface can say the server is
  /// still building its index instead of showing an empty result. Starting a
  /// search for a scope that already has one in flight cancels the older one,
  /// which then completes as [MessageSearchCancelled].
  Future<MessageSearchOutcome> searchMessages(
    MessageSearchRequest request, {
    MessageSearchIndexingCallback? onIndexing,
  });

  /// Abandons the in-flight search for [scope], including any pending retry.
  void cancelSearch(MessageSearchScope scope);
}
