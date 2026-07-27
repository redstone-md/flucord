import 'dart:async';

import '../../domain/message_search.dart';
import '../../domain/message_search_repository.dart';
import 'discord_mapper.dart';
import 'discord_message_search_wire.dart';
import 'discord_rest_client.dart';

/// Sends one search request and hands back the whole answer.
typedef DiscordMessageSearchRequester =
    Future<DiscordApiResponse> Function(
      String path,
      Map<String, Object?> query,
    );

/// Discord's classic message search, including the "still indexing" poll.
///
/// The poll is the part that is easy to get wrong. `202 Accepted` is not a
/// failure and not an empty result: it means the server has not finished
/// building the index for this corpus and wants to be asked again after the
/// delay it names. The client asks up to [maxAttempts] more times and then
/// stops, reporting that the index is still being built rather than pretending
/// the search returned nothing.
final class DiscordMessageSearchService implements MessageSearchRepository {
  DiscordMessageSearchService({
    required DiscordMessageSearchRequester requester,
    DiscordMapper? mapper,
    DelayFunction? delay,
  }) : _request = requester,
       _mapper = mapper ?? DiscordMapper(),
       _delay = delay ?? Future<void>.delayed;

  /// How many times a 202 may be retried. One initial request plus this many
  /// retries is the whole budget; past it the search gives up.
  static const maxAttempts = 5;

  /// Used when the server sends no usable `Retry-After`.
  static const fallbackRetryDelay = Duration(seconds: 5);

  static const _accepted = 202;
  static const _ok = 200;

  final DiscordMessageSearchRequester _request;
  final DiscordMapper _mapper;
  final DelayFunction _delay;

  /// One poll per scope. A second search of the same guild replaces the first,
  /// which is also what stops a slow page from landing after the page the user
  /// actually asked for.
  final Map<String, _MessageSearchPoll> _polls = {};

  String? _currentMemberId;

  /// Who "me" is, so a hit that mentions the account is marked as such. Known
  /// only once a workspace has resolved, which is after this service is built.
  void setCurrentUserId(String? memberId) => _currentMemberId = memberId;

  @override
  Future<MessageSearchOutcome> searchMessages(
    MessageSearchRequest request, {
    MessageSearchIndexingCallback? onIndexing,
  }) async {
    final key = request.scope.key;
    _polls.remove(key)?.cancel();
    final poll = _MessageSearchPoll();
    _polls[key] = poll;
    try {
      return await _poll(request, poll, onIndexing);
    } finally {
      if (identical(_polls[key], poll)) _polls.remove(key);
    }
  }

  @override
  void cancelSearch(MessageSearchScope scope) =>
      _polls.remove(scope.key)?.cancel();

  /// Abandons every in-flight search, for when the transport goes away.
  void close() {
    for (final poll in _polls.values.toList(growable: false)) {
      poll.cancel();
    }
    _polls.clear();
  }

  Future<MessageSearchOutcome> _poll(
    MessageSearchRequest request,
    _MessageSearchPoll poll,
    MessageSearchIndexingCallback? onIndexing,
  ) async {
    final path = DiscordMessageSearchWire.pathFor(request.scope);
    var attempts = 0;
    while (true) {
      if (poll.isCancelled) return const MessageSearchCancelled();
      final response = await _request(
        path,
        DiscordMessageSearchWire.parametersFor(
          request.query,
          attempts: attempts,
        ),
      );
      if (poll.isCancelled) return const MessageSearchCancelled();
      if (response.statusCode == _accepted) {
        attempts++;
        final status = MessageSearchIndexing(
          attempts: attempts,
          retryAfter: response.retryAfter ?? fallbackRetryDelay,
        );
        if (attempts > maxAttempts) return status;
        onIndexing?.call(status);
        if (!await poll.wait(status.retryAfter, _delay)) {
          return const MessageSearchCancelled();
        }
        continue;
      }
      return MessageSearchCompleted(_resultsOf(response, request.scope));
    }
  }

  MessageSearchResults _resultsOf(
    DiscordApiResponse response,
    MessageSearchScope scope,
  ) {
    final payload = response.payload;
    // Discord's own client dispatches nothing for a 2xx that is neither 200 nor
    // 202 and leaves its search spinning forever. Flucord reports it instead:
    // an answer nobody can read is a failure the user can retry, not a state to
    // sit in.
    if (response.statusCode != _ok || payload is! Map) {
      throw DiscordApiException(
        statusCode: response.statusCode,
        message: 'Search returned no readable result',
      );
    }
    return _mapper.searchResults(
      payload.cast<String, Object?>(),
      currentMemberId: _currentMemberId,
      fallbackSpaceId: switch (scope) {
        GuildMessageSearchScope(:final guildId) => guildId,
        ChannelMessageSearchScope() => null,
      },
    );
  }
}

/// One in-flight search, and the pending retry it may be sitting on.
final class _MessageSearchPoll {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Waits out the server's retry delay, returning false when the search was
  /// cancelled instead. The cancellation resolves the wait immediately rather
  /// than letting a five-second timer hold a replaced search alive.
  Future<bool> wait(Duration duration, DelayFunction delay) async {
    await Future.any([delay(duration), _cancelled.future]);
    return !isCancelled;
  }
}
