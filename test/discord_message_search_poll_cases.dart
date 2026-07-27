part of 'discord_message_search_test.dart';

void _pollCases() {
  group('202 poll', () {
    test('retries after the stated delay and then succeeds', () async {
      final transport = _SearchTransport([
        _accepted(retryAfter: '2'),
        _accepted(retryAfter: '0'),
        _ok(),
      ]);
      final delays = <Duration>[];
      final service = _service(transport, delays);
      final indexing = <MessageSearchIndexing>[];

      final outcome = await service.searchMessages(
        _request(),
        onIndexing: indexing.add,
      );

      expect(outcome, isA<MessageSearchCompleted>());
      expect(
        (outcome as MessageSearchCompleted).results.groups.single.hit.body,
        'release notes are up',
      );
      // A missing or zero Retry-After means five seconds, not no wait at all.
      expect(delays, const [Duration(seconds: 2), Duration(seconds: 5)]);
      expect(indexing.map((status) => status.attempts), const [1, 2]);
      // The counter rides on every retry and is absent on the first request.
      expect(transport.queries.first.containsKey('attempts'), isFalse);
      expect(transport.queries[1]['attempts'], '1');
      expect(transport.queries[2]['attempts'], '2');
    });

    test('gives up after five retries and still says it is indexing', () async {
      final transport = _SearchTransport(
        List.generate(7, (_) => _accepted(retryAfter: '1')),
      );
      final service = _service(transport, []);

      final outcome = await service.searchMessages(_request());

      expect(outcome, isA<MessageSearchIndexing>());
      expect((outcome as MessageSearchIndexing).attempts, 6);
      // One initial request plus five retries, and then it stops asking.
      expect(transport.queries, hasLength(6));
    });

    test('cancels the pending retry when a newer search replaces it', () async {
      final gate = Completer<void>();
      final transport = _SearchTransport([_accepted(retryAfter: '1'), _ok()]);
      final service = DiscordMessageSearchService(
        requester: transport.send,
        delay: (duration) => gate.future,
      );

      final first = service.searchMessages(_request());
      await Future<void>.delayed(Duration.zero);
      service.cancelSearch(const GuildMessageSearchScope('111111111111111111'));

      expect(await first, isA<MessageSearchCancelled>());
      // The replaced search never asks again, however long its timer had left.
      expect(transport.queries, hasLength(1));
    });

    test('a second search of the same scope cancels the first', () async {
      final gate = Completer<void>();
      final transport = _SearchTransport([
        _accepted(retryAfter: '1'),
        _ok(),
        _ok(),
      ]);
      final service = DiscordMessageSearchService(
        requester: transport.send,
        delay: (duration) => gate.future,
      );

      final first = service.searchMessages(_request());
      await Future<void>.delayed(Duration.zero);
      final second = service.searchMessages(_request(offset: 25));

      expect(await first, isA<MessageSearchCancelled>());
      expect(await second, isA<MessageSearchCompleted>());
    });

    test('closing abandons everything in flight', () async {
      final gate = Completer<void>();
      final transport = _SearchTransport([_accepted(), _ok()]);
      final service = DiscordMessageSearchService(
        requester: transport.send,
        delay: (duration) => gate.future,
      );

      final pending = service.searchMessages(_request());
      await Future<void>.delayed(Duration.zero);
      service.close();

      expect(await pending, isA<MessageSearchCancelled>());
    });

    test('reports a success nobody can read as a failure', () async {
      final transport = _SearchTransport([
        const DiscordApiResponse(statusCode: 204, headers: {}, payload: null),
      ]);
      final service = _service(transport, []);

      await expectLater(
        service.searchMessages(_request()),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('a channel-scoped search files nothing under a guild', () async {
      final transport = _SearchTransport([_ok()]);
      final service = _service(transport, []);

      final outcome =
          await service.searchMessages(
                MessageSearchRequest(
                  scope: const ChannelMessageSearchScope('222222222222222222'),
                  query: MessageSearchQuery(
                    filters: MessageSearchFilters(content: 'release'),
                  ),
                ),
              )
              as MessageSearchCompleted;

      // The route answers about one channel and never names a guild, so the
      // envelope's own guild_id is the only thing that can place a channel.
      expect(
        outcome.results.channels.map((channel) => channel.spaceId),
        everyElement('111111111111111111'),
      );
    });

    test('marks a hit that mentions the signed-in account', () async {
      final transport = _SearchTransport([_ok()]);
      final service = _service(transport, [])
        ..setCurrentUserId('234567890123456789');

      final outcome =
          await service.searchMessages(_request()) as MessageSearchCompleted;

      expect(outcome.results.groups.single.hit.mentionsCurrentMember, isTrue);
    });
  });
}
