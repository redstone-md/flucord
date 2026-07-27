import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/message_search_controller.dart';
import 'package:flucord/src/application/message_search_grammar.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/message_search.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/presentation/widgets/message_search_panel.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('invites a search before one has been run', (tester) async {
    final harness = await _pump(tester);

    expect(find.text('Search this conversation'), findsOneWidget);
    expect(find.textContaining('from:'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-pager')), findsNothing);
    harness.dispose();
  });

  testWidgets('shows hit groups with their context and jumps to one', (
    tester,
  ) async {
    final harness = await _pump(tester, outcome: _completed());
    await harness.search(tester);

    expect(find.text('3 results'), findsOneWidget);
    expect(find.text('#release'), findsOneWidget);
    // The whole group is drawn, not just the matched message.
    expect(find.textContaining('before the hit'), findsOneWidget);
    expect(find.textContaining('release notes are up'), findsOneWidget);
    expect(find.textContaining('after the hit'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('jump-to-222222222222222222')));
    await tester.pump();

    expect(harness.jumps, const [('333333333333333333', '222222222222222222')]);
    harness.dispose();
  });

  testWidgets('says the server is still indexing, not that nothing matched', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      outcome: const MessageSearchIndexing(
        attempts: 6,
        retryAfter: Duration(seconds: 5),
      ),
    );
    await harness.search(tester);

    expect(find.byKey(const ValueKey('search-indexing')), findsOneWidget);
    expect(find.text('Still indexing'), findsOneWidget);
    expect(find.text('No results found'), findsNothing);

    harness.repository.outcome = _completed();
    await tester.tap(find.byKey(const ValueKey('retry-search')));
    await tester.pumpAndSettle();
    expect(find.text('#release'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('warns that a completed search is still being backfilled', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      outcome: _completed(doingDeepHistoricalIndex: true),
    );
    await harness.search(tester);

    expect(find.byKey(const ValueKey('search-partial-index')), findsOneWidget);
    expect(find.text('#release'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('reports an empty result set as empty', (tester) async {
    final harness = await _pump(
      tester,
      outcome: MessageSearchCompleted(
        MessageSearchResults(totalResults: 0, groups: const []),
      ),
    );
    await harness.search(tester);

    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('0 results'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('offers a retry when the search was rejected', (tester) async {
    final harness = await _pump(tester, error: StateError('rejected'));
    await harness.search(tester);

    expect(find.text('Search unavailable'), findsOneWidget);
    harness.repository
      ..error = null
      ..outcome = _completed();
    await tester.tap(find.byKey(const ValueKey('retry-search')));
    await tester.pumpAndSettle();

    expect(find.text('#release'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('pages through the result set and caps the count', (
    tester,
  ) async {
    final harness = await _pump(tester, outcome: _completed(total: 20000));
    await harness.search(tester);

    expect(find.text('More than 10000 results'), findsOneWidget);
    expect(find.text('Page 1 of 400'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-next-page')));
    await tester.pumpAndSettle();

    expect(harness.repository.requests.last.query.offset, 25);
    expect(find.text('Page 2 of 400'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-previous-page')));
    await tester.pumpAndSettle();
    expect(harness.repository.requests.last.query.offset, 0);
    expect(find.text('Page 1 of 400'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('names an unknown author and an attachment-only hit', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      outcome: MessageSearchCompleted(
        MessageSearchResults(
          totalResults: 1,
          groups: [
            MessageSearchHitGroup(
              messages: [
                ChatMessage(
                  id: '234567890123456789',
                  channelId: '333333333333333333',
                  authorId: '987654321098765432',
                  body: '',
                  sentAt: DateTime.utc(2024, 5),
                  attachments: const [
                    MessageAttachment(
                      id: '111111111111111111',
                      fileName: 'release-notes.md',
                      url: 'local://release-notes.md',
                      size: 12,
                    ),
                  ],
                ),
              ],
              hitIndex: 0,
            ),
          ],
        ),
      ),
    );
    await harness.search(tester);

    // Nothing names this author and nothing names this channel.
    expect(find.text('Unknown user'), findsOneWidget);
    expect(find.text('Unknown channel'), findsOneWidget);
    expect(find.text('release-notes.md'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('names the filters it could not use', (tester) async {
    final harness = await _pump(tester, outcome: _completed());
    await harness.search(tester, text: 'release from:nobody');

    expect(
      find.byKey(const ValueKey('search-unusable-filters')),
      findsOneWidget,
    );
    expect(find.text('Ignored: from:nobody'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('re-runs the search when the order changes', (tester) async {
    final harness = await _pump(tester, outcome: _completed());
    await harness.search(tester);

    await tester.tap(find.byKey(const ValueKey('search-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most relevant').last);
    await tester.pumpAndSettle();

    expect(
      harness.repository.requests.last.query.sort,
      MessageSearchSort.mostRelevant,
    );
    harness.dispose();
  });

  testWidgets('closes and abandons the search', (tester) async {
    final harness = await _pump(tester, outcome: _completed());
    await harness.search(tester);

    await tester.tap(find.byKey(const ValueKey('close-search-panel')));
    await tester.pump();

    expect(harness.closed, 1);
    harness.dispose();
  });

  testWidgets('draws results in a compact window without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = await _pump(tester, outcome: _completed(total: 20000));
    await harness.search(tester);

    expect(find.byKey(const ValueKey('message-search-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    harness.dispose();
  });
}

Future<_Harness> _pump(
  WidgetTester tester, {
  MessageSearchOutcome? outcome,
  Object? error,
}) async {
  final repository = _FakeSearchRepository()
    ..outcome = outcome
    ..error = error;
  final controller = MessageSearchController(() => repository);
  final harness = _Harness(controller, repository);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: MessageSearchPanel(
            controller: controller,
            workspace: _workspace,
            linkLauncher: const _TestLinkLauncher(),
            onClose: () => harness.closed++,
            onJump: (channelId, messageId) =>
                harness.jumps.add((channelId, messageId)),
            onSelectChannel: (_) {},
          ),
        ),
      ),
    ),
  );
  return harness;
}

final class _Harness {
  _Harness(this.controller, this.repository);

  final MessageSearchController controller;
  final _FakeSearchRepository repository;
  final List<(String, String)> jumps = [];
  int closed = 0;

  Future<void> search(WidgetTester tester, {String text = 'release'}) async {
    unawaited(
      controller.search(
        scope: const GuildMessageSearchScope('111111111111111111'),
        text: text,
        grammar: const MessageSearchGrammar(
          channels: [],
          members: [],
          currentMemberId: '123456789012345678',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() => controller.dispose();
}

MessageSearchCompleted _completed({
  int total = 3,
  bool doingDeepHistoricalIndex = false,
}) => MessageSearchCompleted(
  MessageSearchResults(
    totalResults: total,
    doingDeepHistoricalIndex: doingDeepHistoricalIndex,
    groups: [
      MessageSearchHitGroup(
        messages: [
          _message('111111111111111111', 'before the hit'),
          _message('222222222222222222', 'release notes are up'),
          _message('333333333333333333', 'after the hit'),
        ],
        hitIndex: 1,
      ),
    ],
    authors: const [
      Member(
        id: '123456789012345678',
        displayName: 'Ada',
        initials: 'A',
        role: 'Engineer',
        presence: Presence.online,
        colorValue: 0xff456b5a,
      ),
    ],
    channels: const [
      ConversationChannel(
        id: '333333333333333333',
        spaceId: '111111111111111111',
        name: 'release',
        topic: '',
        kind: ChannelKind.text,
      ),
    ],
  ),
);

ChatMessage _message(String id, String body) => ChatMessage(
  id: id,
  channelId: '333333333333333333',
  authorId: '123456789012345678',
  body: body,
  sentAt: DateTime.utc(2024, 5),
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: '111111111111111111',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [],
  members: const [],
  messages: const [],
  currentMemberId: '123456789012345678',
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}

final class _FakeSearchRepository implements MessageSearchRepository {
  final List<MessageSearchRequest> requests = [];

  MessageSearchOutcome? outcome;
  Object? error;

  @override
  Future<MessageSearchOutcome> searchMessages(
    MessageSearchRequest request, {
    MessageSearchIndexingCallback? onIndexing,
  }) async {
    requests.add(request);
    if (error != null) throw error!;
    return outcome ?? const MessageSearchCancelled();
  }

  @override
  void cancelSearch(MessageSearchScope scope) {}
}
