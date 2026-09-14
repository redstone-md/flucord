import 'dart:async';

import 'package:flucord/src/application/friends_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/desktop_relationship_repository.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/friend_suggestion.dart';
import 'package:flucord/src/presentation/widgets/friends_panel.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DiscordRelationship _entry(String id, DiscordRelationshipKind kind) =>
    DiscordRelationship(
      user: DiscordRelationshipUser(id: id, displayName: id),
      kind: kind,
    );

final _graph = [
  _entry('incoming', DiscordRelationshipKind.incomingRequest),
  _entry('outgoing', DiscordRelationshipKind.outgoingRequest),
  _entry('friend', DiscordRelationshipKind.friend),
  _entry('blocked', DiscordRelationshipKind.blocked),
];

void main() {
  group('a suggestion', () {
    test('names somebody, and says why where there is a why', () {
      const named = FriendSuggestion(
        userId: 'user-1',
        displayName: 'Mira',
        reason: 'You have mutual friends',
      );

      expect(named.label, 'Mira');
      expect(const FriendSuggestion(userId: 'user-2').label, 'user-2');
      // Discord's own wording, where it gave one and there is nothing better.
      expect(named.describeReason(), 'You have mutual friends');
      expect(
        const FriendSuggestion(
          userId: 'u',
          mutualFriendCount: 1,
        ).describeReason(),
        '1 mutual friend',
      );
      expect(const FriendSuggestion(userId: 'u').describeReason(), isEmpty);
    });

    test('compares by what it says', () {
      const suggestion = FriendSuggestion(
        userId: 'user-1',
        displayName: 'Mira',
        contactNames: ['a', 'b'],
      );

      expect(
        suggestion,
        const FriendSuggestion(
          userId: 'user-1',
          displayName: 'Mira',
          contactNames: ['a', 'b'],
        ),
      );
      expect(
        suggestion.hashCode,
        const FriendSuggestion(
          userId: 'user-1',
          displayName: 'Mira',
          contactNames: ['a', 'b'],
        ).hashCode,
      );
      expect(
        suggestion ==
            const FriendSuggestion(userId: 'user-1', displayName: 'Mira'),
        isFalse,
      );
      expect(suggestion == Object(), isFalse);
    });
  });

  group('the controller', () {
    test('splits the graph into what each part is for', () {
      final controller = FriendsController(() => _FakeGraph(_graph));
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      expect(controller.requests.map((e) => e.user.id), [
        'incoming',
        'outgoing',
      ]);
      expect(controller.friends.map((e) => e.user.id), ['friend']);
      expect(controller.blocked.map((e) => e.user.id), ['blocked']);
    });

    test('a transport told no graph offers nothing', () async {
      final controller = FriendsController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      expect(controller.all, isEmpty);
      expect(await controller.addFriend('mira'), isFalse);
    });

    test('adding, accepting and removing reach the session', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriend('  mira  '), isTrue);
      // Trimmed: the trailing space is part of typing, not the name.
      expect(graph.added, ['mira']);

      // Accepting is the same call as asking, which is how Discord spells it.
      await controller.acceptRequest(
        _entry('incoming', DiscordRelationshipKind.incomingRequest),
      );
      expect(graph.added, ['mira', 'incoming']);

      await controller.remove(_entry('friend', DiscordRelationshipKind.friend));
      expect(graph.removed, ['friend']);

      await controller.block(_entry('friend', DiscordRelationshipKind.friend));
      expect(graph.blocked, ['friend']);
    });

    test('a blank name asks nothing', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriend('   '), isFalse);
      expect(graph.added, isEmpty);
    });

    test('a refusal is an answer about them, not a fault here', () async {
      final graph = _FakeGraph(_graph)..accept = false;
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriend('mira'), isFalse);

      expect(controller.lastRequestRefused, isTrue);
      expect(controller.error, isNull);
    });

    test('a failure is reported', () async {
      final graph = _FakeGraph(_graph)..failNext = true;
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriend('mira'), isFalse);

      expect(controller.error, isA<StateError>());
    });

    test('a change to the graph reaches whoever is listening', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      // Bind before the first push; nothing listens until somebody reads.
      controller.all;

      graph.push([_entry('new', DiscordRelationshipKind.friend)]);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, greaterThan(0));
    });

    test('a session swap rebinds rather than keeping the old graph', () async {
      final first = _FakeGraph(_graph);
      final second = _FakeGraph([
        _entry('other', DiscordRelationshipKind.friend),
      ]);
      var current = first;
      final controller = FriendsController(() => current);
      addTearDown(controller.dispose);

      expect(controller.friends.single.user.id, 'friend');

      // A sign-out must not leave the last account's friends on screen.
      current = second;
      expect(controller.friends.single.user.id, 'other');
    });

    test('a failed read of suggestions is reported, not thrown', () async {
      final graph = _FakeGraph(_graph)..failSuggestions = true;
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      await controller.loadSuggestions();

      expect(controller.error, isA<StateError>());
      expect(controller.isBusy, isFalse);
    });

    test('the panel flag survives a rebuild, because it lives here', () {
      final controller = FriendsController(() => _FakeGraph(_graph));
      addTearDown(controller.dispose);

      expect(controller.isPanelOpen, isFalse);
      controller.togglePanel();
      expect(controller.isPanelOpen, isTrue);
      controller.togglePanel();
      expect(controller.isPanelOpen, isFalse);
    });
  });

  group('the panel', () {
    testWidgets('groups the graph and names what each entry is', (
      tester,
    ) async {
      await _pump(tester, _FakeGraph(_graph));

      expect(find.text('Requests — 2'), findsOneWidget);
      expect(find.text('Friends — 1'), findsOneWidget);
      expect(find.text('Blocked — 1'), findsOneWidget);
      expect(find.text('Wants to be friends'), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget);
      // The action says what it does to this particular entry.
      expect(find.text('Ignore'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
    });

    testWidgets('only an incoming request can be accepted', (tester) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);

      expect(find.byKey(const ValueKey('friend-accept-incoming')), findsOne);
      expect(
        find.byKey(const ValueKey('friend-accept-outgoing')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('friend-accept-incoming')));
      await tester.pumpAndSettle();

      expect(graph.added, ['incoming']);
    });

    testWidgets('somebody is added by name, and the field clears', (
      tester,
    ) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);

      await tester.enterText(
        find.byKey(const ValueKey('friends-add-username')),
        'mira',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friends-add')));
      await tester.pumpAndSettle();

      expect(graph.added, ['mira']);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('friends-add-username')),
            )
            .controller
            ?.text,
        isEmpty,
      );
    });

    testWidgets('a refused request is explained, not shown as a crash', (
      tester,
    ) async {
      await _pump(tester, _FakeGraph(_graph)..accept = false);

      await tester.enterText(
        find.byKey(const ValueKey('friends-add-username')),
        'mira',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friends-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('friends-refused')), findsOneWidget);
    });

    testWidgets('removing an entry reaches the session', (tester) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);

      await tester.tap(find.byKey(const ValueKey('friend-remove-friend')));
      await tester.pumpAndSettle();

      expect(graph.removed, ['friend']);
    });

    testWidgets('a relationship nobody asked for still reads as something', (
      tester,
    ) async {
      // An implicit relationship is somebody the account plays with, and one
      // newer than this build is a kind it has never heard of. Neither is a
      // blank row.
      await _pump(
        tester,
        _FakeGraph([
          _entry('plays', DiscordRelationshipKind.implicit),
          _entry('mystery', DiscordRelationshipKind.unknown),
        ]),
      );

      expect(find.text('You play together'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('presence is shown beside a name the session knows', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeGraph(_graph),
        presenceOf: (id) => id == 'friend' ? Presence.online : null,
      );

      expect(
        find.byKey(const ValueKey('friend-presence-friend')),
        findsOneWidget,
      );
      // Somebody the session has no presence for gets no indicator rather
      // than a grey one that claims they are offline.
      expect(
        find.byKey(const ValueKey('friend-presence-incoming')),
        findsNothing,
      );
    });

    testWidgets('suggestions are offered, and can be answered either way', (
      tester,
    ) async {
      final graph = _FakeGraph(_graph)
        ..suggestions = const [
          FriendSuggestion(
            userId: 'maybe',
            displayName: 'Maybe',
            mutualFriendCount: 2,
          ),
        ];
      await _pump(tester, graph);

      expect(find.text('You may know — 1'), findsOneWidget);
      expect(find.text('2 mutual friends'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('suggestion-add-maybe')));
      await tester.pumpAndSettle();
      expect(graph.added, ['maybe']);

      await tester.tap(find.byKey(const ValueKey('suggestion-dismiss-maybe')));
      await tester.pumpAndSettle();
      expect(graph.dismissed, ['maybe']);
      expect(find.byKey(const ValueKey('suggestion-maybe')), findsNothing);
    });

    testWidgets('the panel asks for suggestions when it opens', (tester) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);

      expect(graph.suggestionLoads, 1);
    });

    testWidgets('somebody already in the graph is not suggested', (
      tester,
    ) async {
      // A suggestion that arrived before the friendship was made would
      // otherwise offer to introduce two people who already know each other.
      await _pump(
        tester,
        _FakeGraph(_graph)
          ..suggestions = const [
            FriendSuggestion(userId: 'friend', displayName: 'Friend'),
          ],
      );

      expect(find.byKey(const ValueKey('suggestion-friend')), findsNothing);
    });

    testWidgets('an account with nobody says so', (tester) async {
      await _pump(tester, _FakeGraph(const []));

      expect(find.byKey(const ValueKey('friends-empty')), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeGraph graph, {
  Presence? Function(String userId)? presenceOf,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = FriendsController(() => graph);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: FriendsPanel(controller: controller, presenceOf: presenceOf),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeGraph implements DesktopRelationshipRepository {
  _FakeGraph(this._entries);

  List<DiscordRelationship> _entries;
  final StreamController<List<DiscordRelationship>> _updates =
      StreamController.broadcast();
  final List<String> added = [];
  final List<String> removed = [];
  final List<String> blocked = [];
  bool accept = true;
  bool failNext = false;

  void push(List<DiscordRelationship> next) {
    _entries = next;
    _updates.add(next);
  }

  @override
  List<DiscordRelationship> get relationships => _entries;

  @override
  Stream<List<DiscordRelationship>> get relationshipUpdates => _updates.stream;

  @override
  Future<bool> addFriend(String userId) async {
    if (failNext) {
      failNext = false;
      throw StateError('add failed');
    }
    if (!accept) return false;
    added.add(userId);
    return true;
  }

  @override
  Future<bool> removeRelationship(String userId) async {
    if (!accept) return false;
    removed.add(userId);
    return true;
  }

  List<FriendSuggestion> suggestions = const [];
  final List<String> dismissed = [];
  int suggestionLoads = 0;

  @override
  List<FriendSuggestion> get friendSuggestions => suggestions;

  bool failSuggestions = false;

  @override
  Future<void> loadFriendSuggestions() async {
    if (failSuggestions) {
      failSuggestions = false;
      throw StateError('suggestions failed');
    }
    suggestionLoads++;
  }

  @override
  Future<bool> dismissSuggestion(String userId) async {
    if (!accept) return false;
    dismissed.add(userId);
    suggestions = [
      for (final entry in suggestions)
        if (entry.userId != userId) entry,
    ];
    return true;
  }

  @override
  Future<bool> blockUser(String userId) async {
    if (!accept) return false;
    blocked.add(userId);
    return true;
  }
}
