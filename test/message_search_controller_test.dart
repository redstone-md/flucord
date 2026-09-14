import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/message_search_controller.dart';
import 'package:flucord/src/application/message_search_grammar.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_search.dart';
import 'package:flucord/src/domain/message_search_repository.dart';

void main() {
  test('answers a search with the page it asked for', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 30));
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    await controller.search(
      scope: _scope,
      text: 'from:Ada release',
      grammar: _grammar,
    );

    expect(controller.status, MessageSearchStatus.ready);
    expect(controller.results!.groups, hasLength(1));
    expect(controller.pageCount, 2);
    expect(controller.text, 'from:Ada release');
    expect(repository.requests.single.query.filters.authorIds, const [
      '123456789012345678',
    ]);
    expect(repository.requests.single.query.offset, 0);
  });

  test('refuses a line that resolves to no parameters', () async {
    final repository = _FakeSearchRepository();
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    await controller.search(
      scope: _scope,
      text: 'from:nobody',
      grammar: _grammar,
    );

    // An empty query object asks the server for every message in the guild.
    expect(repository.requests, isEmpty);
    expect(controller.status, MessageSearchStatus.idle);
    expect(controller.hasQuery, isFalse);
    expect(controller.unresolved, const ['from:nobody']);
  });

  test('says the server is indexing rather than showing no results', () async {
    final repository = _FakeSearchRepository()
      ..outcome = const MessageSearchIndexing(
        attempts: 6,
        retryAfter: Duration(seconds: 5),
      );
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    expect(controller.status, MessageSearchStatus.indexing);
    expect(controller.indexing!.attempts, 6);
    expect(controller.results, isNull);
  });

  test('reports each 202 while the retries are still running', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 1))
      ..indexingReports = const [
        MessageSearchIndexing(attempts: 1, retryAfter: Duration(seconds: 2)),
      ];
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);
    final seen = <MessageSearchStatus>[];
    controller.addListener(() => seen.add(controller.status));

    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    expect(seen, const [
      MessageSearchStatus.searching,
      MessageSearchStatus.indexing,
      MessageSearchStatus.ready,
    ]);
    expect(controller.indexing, isNull);
  });

  test('turns a rejected search into a failure that can be retried', () async {
    final repository = _FakeSearchRepository()..error = StateError('rejected');
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    await controller.search(scope: _scope, text: 'release', grammar: _grammar);
    expect(controller.status, MessageSearchStatus.failed);
    expect(controller.error, isStateError);

    repository
      ..error = null
      ..outcome = MessageSearchCompleted(_results(total: 1));
    await controller.retry();

    expect(controller.status, MessageSearchStatus.ready);
    expect(repository.requests, hasLength(2));
  });

  test('pages by fixed blocks of 25 and clamps the reachable range', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 20000));
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);
    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    await controller.goToPage(2);
    expect(repository.requests.last.query.offset, 50);

    await controller.goToPage(9999);
    expect(repository.requests.last.query.offset, MessageSearchQuery.maxOffset);

    // Asking for the page already shown is not a second request.
    final before = repository.requests.length;
    await controller.goToPage(MessageSearchQuery.maxPageIndex);
    expect(repository.requests, hasLength(before));
    expect(controller.pageCount, MessageSearchQuery.maxPageIndex + 1);
    expect(controller.results!.isTotalLimited, isTrue);
  });

  test('a new order restarts the result set at the first page', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 100));
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);
    await controller.search(scope: _scope, text: 'release', grammar: _grammar);
    await controller.goToPage(3);

    await controller.setSort(MessageSearchSort.mostRelevant);

    expect(repository.requests.last.query.offset, 0);
    expect(repository.requests.last.query.sort, MessageSearchSort.mostRelevant);
    // Choosing the order already in force changes nothing.
    final before = repository.requests.length;
    await controller.setSort(MessageSearchSort.mostRelevant);
    expect(repository.requests, hasLength(before));
  });

  test(
    'an order chosen with nothing searched sticks for the next one',
    () async {
      final repository = _FakeSearchRepository()
        ..outcome = MessageSearchCompleted(_results(total: 1));
      final controller = MessageSearchController(() => repository);
      addTearDown(controller.dispose);

      await controller.setSort(MessageSearchSort.oldest);
      expect(repository.requests, isEmpty);
      expect(controller.sort, MessageSearchSort.oldest);

      await controller.search(
        scope: _scope,
        text: 'release',
        grammar: _grammar,
      );
      expect(repository.requests.single.query.sort, MessageSearchSort.oldest);
    },
  );

  test('a page that lands after the reader moved on is discarded', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 1, body: 'stale'))
      ..hold = true;
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    final stale = controller.search(
      scope: _scope,
      text: 'release',
      grammar: _grammar,
    );
    repository
      ..hold = false
      ..outcome = MessageSearchCompleted(_results(total: 1, body: 'fresh'));
    await controller.search(scope: _scope, text: 'notes', grammar: _grammar);
    repository.release();
    await stale;

    expect(controller.results!.groups.single.hit.body, 'fresh');
    expect(controller.text, 'notes');
  });

  test('a cancelled search leaves the newer one alone', () async {
    final repository = _FakeSearchRepository()
      ..outcome = const MessageSearchCancelled();
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);

    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    expect(controller.status, MessageSearchStatus.searching);
    expect(controller.results, isNull);
  });

  test('clearing abandons the search and empties the panel', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 1));
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);
    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    controller.clear();

    expect(repository.cancelled, const [_scope]);
    expect(controller.results, isNull);
    expect(controller.text, isEmpty);
    expect(controller.status, MessageSearchStatus.idle);
    expect(controller.pageIndex, 0);
    expect(controller.pageCount, 0);
    // Nothing to page or re-run once the panel is empty.
    await controller.goToPage(1);
    await controller.retry();
    expect(repository.requests, hasLength(1));
  });

  test('names a channel the workspace never loaded', () async {
    final repository = _FakeSearchRepository()
      ..outcome = MessageSearchCompleted(_results(total: 1));
    final controller = MessageSearchController(() => repository);
    addTearDown(controller.dispose);
    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    expect(controller.channelNameFor('222222222222222222'), 'release');
    expect(controller.channelNameFor('987654321098765432'), isNull);
  });

  test('a transport with no search plane does nothing', () async {
    final controller = MessageSearchController(() => null);
    addTearDown(controller.dispose);

    expect(controller.isSupported, isFalse);
    await controller.search(scope: _scope, text: 'release', grammar: _grammar);

    // No spinner for a request that was never sent.
    expect(controller.status, MessageSearchStatus.idle);
    expect(controller.results, isNull);
  });
}

const _scope = GuildMessageSearchScope('111111111111111111');

const _grammar = MessageSearchGrammar(
  channels: [],
  members: [
    Member(
      id: '123456789012345678',
      displayName: 'Ada',
      initials: 'A',
      role: 'Engineer',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  currentMemberId: '123456789012345678',
);

MessageSearchResults _results({required int total, String body = 'release'}) =>
    MessageSearchResults(
      totalResults: total,
      groups: [
        MessageSearchHitGroup(
          messages: [
            ChatMessage(
              id: '234567890123456789',
              channelId: '222222222222222222',
              authorId: '123456789012345678',
              body: body,
              sentAt: DateTime.utc(2024, 5),
            ),
          ],
          hitIndex: 0,
        ),
      ],
      channels: const [
        ConversationChannel(
          id: '222222222222222222',
          spaceId: '111111111111111111',
          name: 'release',
          topic: '',
          kind: ChannelKind.text,
        ),
      ],
    );

final class _FakeSearchRepository implements MessageSearchRepository {
  final List<MessageSearchRequest> requests = [];
  final List<MessageSearchScope> cancelled = [];
  List<MessageSearchIndexing> indexingReports = const [];

  MessageSearchOutcome? outcome;
  Object? error;
  bool hold = false;
  Completer<void>? _gate;

  void release() => _gate?.complete();

  @override
  Future<MessageSearchOutcome> searchMessages(
    MessageSearchRequest request, {
    MessageSearchIndexingCallback? onIndexing,
  }) async {
    requests.add(request);
    for (final report in indexingReports) {
      onIndexing?.call(report);
    }
    if (hold) {
      final gate = _gate = Completer<void>();
      await gate.future;
    }
    if (error != null) throw error!;
    return outcome!;
  }

  @override
  void cancelSearch(MessageSearchScope scope) => cancelled.add(scope);
}
