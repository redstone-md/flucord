import 'dart:async';

import 'package:flucord/src/application/friends_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/desktop_relationship_repository.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/friend_suggestion.dart';
import 'package:flucord/src/domain/relationship_request.dart';
import 'package:flucord/src/presentation/widgets/friends_panel.dart';
import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/focus_traversal.dart';

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
    test('drops a captcha held for an account it no longer acts for', () async {
      final first = _FakeGraph(_graph)
        ..wantsCaptcha = const DiscordRemoteAuthCaptchaChallenge(
          siteKey: 'site',
          service: 'hcaptcha',
          userAgent: 'Flucord',
        );
      final second = _FakeGraph(_graph);
      var current = first;
      final controller = FriendsController(() => current);
      addTearDown(controller.dispose);

      expect(await controller.addFriendByUsername('mira'), isFalse);
      expect(controller.captcha, isNotNull);

      current = second;

      expect(controller.captcha, isNull);
      expect(await controller.solveCaptcha('solved'), isFalse);
      expect(second.addedByName, isEmpty);
    });

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
      expect(await controller.addFriendByUsername('mira'), isFalse);
    });

    test('adding, accepting and removing reach the session', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriendByUsername('  mira  '), isTrue);
      // Trimmed: the trailing space is part of typing, not the name.
      expect(graph.addedByName, ['mira']);

      // Accepting is the same call as asking, which is how Discord spells it.
      await controller.acceptRequest(
        _entry('incoming', DiscordRelationshipKind.incomingRequest),
      );
      expect(graph.added, ['incoming']);

      await controller.remove(_entry('friend', DiscordRelationshipKind.friend));
      expect(graph.removed, ['friend']);

      await controller.block(_entry('friend', DiscordRelationshipKind.friend));
      expect(graph.blocked, ['friend']);
    });

    test('a blank name asks nothing', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriendByUsername('   '), isFalse);
      expect(graph.addedByName, isEmpty);
    });

    test('a refusal is an answer about them, not a fault here', () async {
      final graph = _FakeGraph(_graph)..accept = false;
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriendByUsername('mira'), isFalse);

      expect(controller.refusal?.reason, RelationshipRefusal.other);
      expect(controller.error, isNull);
    });

    test('a failure is reported', () async {
      final graph = _FakeGraph(_graph)..failNext = true;
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      expect(await controller.addFriendByUsername('mira'), isFalse);

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

    test('suggestions load while another request is on its way', () async {
      final graph = _FakeGraph(_graph);
      final controller = FriendsController(() => graph);
      addTearDown(controller.dispose);

      final adding = controller.addFriendByUsername('mira');
      await controller.loadSuggestions();
      await adding;

      expect(graph.suggestionLoads, 1);
    });

    test('a request is offered only to somebody not already in reach', () {
      final controller = FriendsController(() => _FakeGraph(_graph));
      addTearDown(controller.dispose);

      expect(controller.canBefriend('stranger'), isTrue);
      expect(controller.canBefriend('incoming'), isTrue);
      expect(controller.canBefriend('friend'), isFalse);
      expect(controller.canBefriend('outgoing'), isFalse);
      expect(controller.canBefriend('blocked'), isFalse);
      expect(
        controller.relationshipWith('friend')?.kind,
        DiscordRelationshipKind.friend,
      );
    });

    test('the panel flag survives a rebuild, because it lives here', () {
      final controller = FriendsController(() => _FakeGraph(_graph));
      addTearDown(controller.dispose);

      expect(controller.isPanelOpen, isFalse);
      controller.openPanel();
      // Pressing Friends again keeps the page, as Discord's row does.
      controller.openPanel();
      expect(controller.isPanelOpen, isTrue);
      controller.closePanel();
      expect(controller.isPanelOpen, isFalse);
    });
  });

  group('the page header', () {
    testWidgets('names the page and offers the four lists and Add friend', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeGraph(_graph),
        inbox: const SizedBox(key: ValueKey('inbox-slot')),
      );

      final header = find.byKey(const ValueKey('friends-header'));
      expect(tester.getSize(header).height, 48);
      expect(
        find.descendant(of: header, matching: find.text('Friends')),
        findsOneWidget,
      );
      for (final label in ['Online', 'All', 'Pending', 'Blocked']) {
        expect(
          find.descendant(of: header, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: header, matching: find.text('Add friend')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('inbox-slot')),
        ),
        findsOneWidget,
      );
      // Online is where the page opens.
      expect(_tabSemantics(tester, 'online'), isSemantics(isSelected: true));
      expect(_tabSemantics(tester, 'pending'), isSemantics(isSelected: false));
    });

    testWidgets('the tabs are reached and switched with the keyboard', (
      tester,
    ) async {
      await _pump(tester, _FakeGraph(_graph));

      await tabTo(tester, _tab('pending'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Pending 2'), findsOneWidget);

      await tabTo(tester, _tab('add'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friends-add-username')), findsOne);
    });
  });

  group('the Online list', () {
    testWidgets('holds the friends who are not offline', (tester) async {
      await _pump(
        tester,
        _FakeGraph([
          ..._graph,
          _entry('away', DiscordRelationshipKind.friend),
          _entry('gone', DiscordRelationshipKind.friend),
        ]),
        presenceOf: (id) => switch (id) {
          'friend' => Presence.online,
          'away' => Presence.idle,
          'gone' => Presence.offline,
          _ => null,
        },
      );

      expect(find.text('Online 2'), findsOneWidget);
      expect(_row('friend'), findsOneWidget);
      expect(_row('away'), findsOneWidget);
      expect(_row('gone'), findsNothing);
      // Requests and blocks have their own tabs.
      expect(_row('incoming'), findsNothing);
      expect(_row('blocked'), findsNothing);
    });

    testWidgets('says so when nobody is online', (tester) async {
      await _pump(tester, _FakeGraph(_graph));

      expect(find.byKey(const ValueKey('friends-empty')), findsOneWidget);
      expect(find.text('No friends are online right now.'), findsOneWidget);
    });

    testWidgets('a friend row opens the DM', (tester) async {
      final messaged = <String>[];
      await _pump(
        tester,
        _FakeGraph(_graph),
        presenceOf: (id) => Presence.online,
        onMessage: messaged.add,
      );

      await tester.tap(find.byKey(const ValueKey('friend-message-friend')));
      expect(messaged, ['friend']);
    });
  });

  group('the All list', () {
    testWidgets('holds every friend, with presence where it is known', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeGraph([..._graph, _entry('gone', DiscordRelationshipKind.friend)]),
        presenceOf: (id) => id == 'friend' ? Presence.online : null,
      );
      await _open(tester, 'all');

      expect(find.text('All friends 2'), findsOneWidget);
      expect(_row('friend'), findsOneWidget);
      expect(_row('gone'), findsOneWidget);
      expect(_row('incoming'), findsNothing);
      expect(_badge('friend'), findsOneWidget);
      // Somebody the session has no presence for gets no indicator rather
      // than a grey one that claims they are offline.
      expect(_badge('gone'), findsNothing);
    });

    testWidgets('removing a friend reaches the session', (tester) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);
      await _open(tester, 'all');

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
      await _open(tester, 'all');

      expect(find.text('Other 2'), findsOneWidget);
      expect(find.text('You play together'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
    });
  });

  group('the Pending list', () {
    testWidgets('holds requests both ways, each with its own answer', (
      tester,
    ) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);
      await _open(tester, 'pending');

      expect(find.text('Pending 2'), findsOneWidget);
      expect(find.text('Wants to be friends'), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget);
      expect(_row('friend'), findsNothing);
      // The action says what it does to this particular entry.
      expect(find.text('Ignore'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('friend-accept-outgoing')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('friend-accept-incoming')));
      await tester.pumpAndSettle();
      expect(graph.added, ['incoming']);

      await tester.tap(find.byKey(const ValueKey('friend-remove-outgoing')));
      await tester.pumpAndSettle();
      expect(graph.removed, ['outgoing']);
    });

    testWidgets('says so when nothing is waiting', (tester) async {
      await _pump(
        tester,
        _FakeGraph([_entry('friend', DiscordRelationshipKind.friend)]),
      );
      await _open(tester, 'pending');

      expect(find.text('No pending requests.'), findsOneWidget);
    });
  });

  group('the Blocked list', () {
    testWidgets('holds blocked people, and unblocks one', (tester) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);
      await _open(tester, 'blocked');

      expect(find.text('Blocked 1'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
      expect(_row('friend'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('friend-remove-blocked')));
      await tester.pumpAndSettle();

      expect(graph.removed, ['blocked']);
    });

    testWidgets('says so when nobody is blocked', (tester) async {
      await _pump(tester, _FakeGraph(const []));
      await _open(tester, 'blocked');

      expect(find.text('You have not blocked anyone.'), findsOneWidget);
    });
  });

  group('the Add friend view', () {
    testWidgets('somebody is added by name, and the field clears', (
      tester,
    ) async {
      final graph = _FakeGraph(_graph);
      await _pump(tester, graph);
      await _open(tester, 'add');

      await tester.enterText(
        find.byKey(const ValueKey('friends-add-username')),
        'mira',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friends-add')));
      await tester.pumpAndSettle();

      expect(graph.addedByName, ['mira']);
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
      await _open(tester, 'add');

      await tester.enterText(
        find.byKey(const ValueKey('friends-add-username')),
        'mira',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friends-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('friends-refused')), findsOneWidget);
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
      await _open(tester, 'add');

      expect(find.text('You may know 1'), findsOneWidget);
      expect(find.text('2 mutual friends'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('suggestion-add-maybe')));
      await tester.pumpAndSettle();
      expect(graph.added, ['maybe']);

      await tester.tap(find.byKey(const ValueKey('suggestion-dismiss-maybe')));
      await tester.pumpAndSettle();
      expect(graph.dismissed, ['maybe']);
      expect(find.byKey(const ValueKey('suggestion-maybe')), findsNothing);
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
      await _open(tester, 'add');

      expect(find.byKey(const ValueKey('suggestion-friend')), findsNothing);
    });
  });

  testWidgets('the panel asks for suggestions when it opens', (tester) async {
    final graph = _FakeGraph(_graph);
    await _pump(tester, graph);

    expect(graph.suggestionLoads, 1);
  });
}

Finder _tab(String name) => find.byKey(ValueKey('friends-tab-$name'));

Finder _row(String userId) => find.byKey(ValueKey('friend-$userId'));

/// The presence badge in the row of [userId].
Finder _badge(String userId) =>
    find.descendant(of: _row(userId), matching: find.byType(PresenceIndicator));

SemanticsNode _tabSemantics(WidgetTester tester, String name) =>
    tester.getSemantics(_tab(name));

Future<void> _open(WidgetTester tester, String tab) async {
  await tester.tap(_tab(tab));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _FakeGraph graph, {
  Presence? Function(String userId)? presenceOf,
  ValueChanged<String>? onMessage,
  Widget? inbox,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = FriendsController(() => graph);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: FriendsPanel(
          controller: controller,
          presenceOf: presenceOf,
          onMessage: onMessage,
          inbox: inbox,
        ),
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
  final List<String> addedByName = [];
  final List<String> removed = [];
  final List<String> blocked = [];
  bool accept = true;
  bool failNext = false;

  /// When set, a request without an answer is held for this captcha.
  DiscordRemoteAuthCaptchaChallenge? wantsCaptcha;

  void push(List<DiscordRelationship> next) {
    _entries = next;
    _updates.add(next);
  }

  @override
  List<DiscordRelationship> get relationships => _entries;

  @override
  Stream<List<DiscordRelationship>> get relationshipUpdates => _updates.stream;

  @override
  Future<RelationshipResult> send(
    RelationshipRequest request, {
    DiscordCaptchaAnswer? captcha,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('request failed');
    }
    if (!accept) return const RelationshipRefused(RelationshipRefusal.other);
    if (wantsCaptcha case final challenge? when captcha == null) {
      return RelationshipCaptchaRequired(challenge);
    }
    switch (request) {
      case BefriendUser(:final userId):
        added.add(userId);
      case BefriendUsername(:final username):
        addedByName.add(username);
      case RemoveRelationship(:final userId):
        removed.add(userId);
      case BlockUser(:final userId):
        blocked.add(userId);
      case DismissSuggestion(:final userId):
        dismissed.add(userId);
        suggestions = [
          for (final entry in suggestions)
            if (entry.userId != userId) entry,
        ];
    }
    return const RelationshipDone();
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
}
