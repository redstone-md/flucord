import 'package:flucord/src/data/discord/discord_relationship_service.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/friend_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ready() => {
  'relationships': [
    {
      'id': 'user-1',
      'type': 1,
      'user': {'id': 'user-1', 'username': 'mira', 'global_name': 'Mira'},
    },
    {
      'id': 'user-2',
      'type': 3,
      'user': {'id': 'user-2', 'username': 'ada'},
    },
    {
      'id': 'user-3',
      'type': 4,
      'user': {'id': 'user-3', 'username': 'lena'},
    },
    {'id': 'user-4', 'type': 2},
    // Older builds send the user in a table beside the relationships.
    {'id': 'user-5', 'type': 1},
    {'type': 1},
    'nonsense',
  ],
  'users': [
    {'id': 'user-4', 'username': 'blocked-one'},
    {'id': 'user-5', 'username': 'tabled', 'global_name': 'Tabled'},
  ],
};

void main() {
  test('READY carries the whole graph, requests first', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    expect(service.accept('READY', _ready()), isTrue);

    final relationships = service.relationships;
    expect(relationships.map((r) => r.user.id), [
      // Incoming first: it is the one that wants an answer.
      'user-2',
      'user-3',
      'user-1',
      'user-5',
      'user-4',
    ]);
    expect(relationships.first.kind, DiscordRelationshipKind.incomingRequest);
    expect(relationships[1].kind, DiscordRelationshipKind.outgoingRequest);
    expect(relationships.last.kind, DiscordRelationshipKind.blocked);
    // A relationship whose user only appears in the table still has a name.
    expect(
      relationships.firstWhere((r) => r.user.id == 'user-5').user.displayName,
      'Tabled',
    );
    expect(
      relationships.firstWhere((r) => r.user.id == 'user-4').user.displayName,
      'blocked-one',
    );
  });

  test('a nickname this account gave wins over Discord\'s own name', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    service.accept('READY', {
      'relationships': [
        {
          'id': 'user-1',
          'type': 1,
          'nickname': 'Mimi',
          'user': {'id': 'user-1', 'username': 'mira', 'global_name': 'Mira'},
        },
      ],
    });

    // It is the name whoever set it will recognise.
    expect(service.relationships.single.user.displayName, 'Mimi');
  });

  test('a friendship made later joins the graph', () async {
    final service = DiscordRelationshipService();
    final seen = <int>[];
    final subscription = service.updates.listen(
      (list) => seen.add(list.length),
    );
    addTearDown(subscription.cancel);
    service.accept('READY', _ready());

    expect(
      service.accept('RELATIONSHIP_ADD', {
        'relationship': {
          'id': 'user-9',
          'type': 4,
          'user': {'id': 'user-9', 'username': 'new'},
        },
      }),
      isTrue,
    );

    expect(service.relationships, hasLength(6));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [5, 6]);
    await service.close();
  });

  test('an accepted request becomes a friendship in place', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    service.accept('READY', _ready());

    service.accept('RELATIONSHIP_UPDATE', {
      'relationship': {
        'id': 'user-2',
        'type': 1,
        'user': {'id': 'user-2', 'username': 'ada'},
      },
    });

    // Revised, not duplicated: it is the same person.
    expect(service.relationships, hasLength(5));
    expect(
      service.relationships.firstWhere((r) => r.user.id == 'user-2').kind,
      DiscordRelationshipKind.friend,
    );
  });

  test('a removed relationship leaves', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    service.accept('READY', _ready());

    expect(
      service.accept('RELATIONSHIP_REMOVE', {
        'relationship': {'id': 'user-1'},
      }),
      isTrue,
    );

    expect(
      service.relationships.map((r) => r.user.id),
      isNot(contains('user-1')),
    );
    // Removing somebody who is not there changes nothing.
    expect(
      service.accept('RELATIONSHIP_REMOVE', {
        'relationship': {'id': 'user-1'},
      }),
      isFalse,
    );
  });

  test('a fresh session replaces the graph rather than adding to it', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    service.accept('READY', _ready());

    service.accept('READY', {
      'relationships': [
        {
          'id': 'user-7',
          'type': 1,
          'user': {'id': 'user-7', 'username': 'only'},
        },
      ],
    });

    // Anything held from before may have been undone on another device.
    expect(service.relationships.map((r) => r.user.id), ['user-7']);
  });

  test('a suggestion says who and why', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    expect(
      service.accept('FRIEND_SUGGESTION_CREATE', {
        'suggestion': {
          'suggested_user': {
            'id': 'user-9',
            'username': 'mira',
            'global_name': 'Mira',
          },
          'reasons': [
            {'type': 1, 'name': 'You have mutual friends'},
          ],
          'mutual_friends_count': 3,
        },
      }),
      isTrue,
    );

    final suggestion = service.suggestions.single;
    expect(suggestion.userId, 'user-9');
    expect(suggestion.label, 'Mira');
    expect(suggestion.mutualFriendCount, 3);
    expect(suggestion.describeReason(), '3 mutual friends');
  });

  test('contact names are only shown when two hide each other', () {
    // Discord sends them at two or more so a single contact cannot be
    // singled out; anything shorter is dropped rather than shown alone.
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    service.accept('FRIEND_SUGGESTION_CREATE', {
      'suggestion': {
        'suggested_user': {'id': 'user-1', 'username': 'one'},
        'contact_names': ['Mira'],
      },
    });
    service.accept('FRIEND_SUGGESTION_CREATE', {
      'suggestion': {
        'suggested_user': {'id': 'user-2', 'username': 'two'},
        'contact_names': ['Mira', 'M. Chen', 'Third'],
      },
    });

    expect(service.suggestions.first.contactNames, isEmpty);
    expect(service.suggestions.first.describeReason(), isEmpty);
    // Only the first two are kept, which is what Discord's own client shows.
    expect(service.suggestions.last.contactNames, ['Mira', 'M. Chen']);
    expect(
      service.suggestions.last.describeReason(),
      'In your contacts as Mira and M. Chen',
    );
  });

  test('a suggestion repeated is not a second suggestion', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    final payload = {
      'suggestion': {
        'suggested_user': {'id': 'user-9', 'username': 'mira'},
      },
    };

    expect(service.accept('FRIEND_SUGGESTION_CREATE', payload), isTrue);
    expect(service.accept('FRIEND_SUGGESTION_CREATE', payload), isFalse);
    expect(service.suggestions, hasLength(1));
    // Somebody Discord named nothing for still reads as a person, by id.
    expect(service.suggestions.single.label, 'mira');
  });

  test('a withdrawn suggestion leaves', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    service.accept('FRIEND_SUGGESTION_CREATE', {
      'suggestion': {
        'suggested_user': {'id': 'user-9', 'username': 'mira'},
      },
    });

    expect(
      service.accept('FRIEND_SUGGESTION_DELETE', {
        'suggested_user_id': 'user-9',
      }),
      isTrue,
    );
    expect(service.suggestions, isEmpty);
    // Withdrawing one that is not held changes nothing.
    expect(
      service.accept('FRIEND_SUGGESTION_DELETE', {
        'suggested_user_id': 'user-9',
      }),
      isFalse,
    );
  });

  test('a suggestion naming nobody is not one', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    expect(
      service.accept('FRIEND_SUGGESTION_CREATE', const {
        'suggestion': 'nonsense',
      }),
      isFalse,
    );
    expect(
      service.accept('FRIEND_SUGGESTION_CREATE', const {
        'suggestion': {'suggested_user': 'nonsense'},
      }),
      isFalse,
    );
    expect(
      service.accept('FRIEND_SUGGESTION_CREATE', const {
        'suggestion': {
          'suggested_user': {'username': 'no id'},
        },
      }),
      isFalse,
    );
    expect(service.suggestions, isEmpty);
  });

  test('the route replaces what is held', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);
    service.accept('FRIEND_SUGGESTION_CREATE', {
      'suggestion': {
        'suggested_user': {'id': 'user-1', 'username': 'one'},
      },
    });

    service.replaceSuggestions([
      const FriendSuggestion(userId: 'user-2', displayName: 'Two'),
    ]);

    expect(service.suggestions.single.userId, 'user-2');
    service.forgetSuggestion('user-2');
    expect(service.suggestions, isEmpty);
  });

  test('anything else changes nothing', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    expect(service.accept('MESSAGE_CREATE', const {}), isFalse);
    expect(service.accept('RELATIONSHIP_ADD', const {}), isFalse);
    expect(
      service.accept('RELATIONSHIP_REMOVE', const {'relationship': 'nonsense'}),
      isFalse,
    );
    expect(
      service.accept('READY', const {'relationships': 'nonsense'}),
      isTrue,
    );
    expect(service.relationships, isEmpty);
  });

  test('a kind newer than this build reads as unknown', () {
    final service = DiscordRelationshipService();
    addTearDown(service.close);

    service.accept('READY', {
      'relationships': [
        {
          'id': 'user-1',
          'type': 99,
          'user': {'id': 'user-1', 'username': 'mystery'},
        },
        {
          'id': 'user-2',
          'type': 5,
          'user': {'id': 'user-2', 'username': 'plays-with'},
        },
      ],
    });

    expect(
      service.relationships.map((r) => r.kind),
      // The implicit one keeps its own kind: it is somebody the account plays
      // with rather than somebody it asked for.
      [DiscordRelationshipKind.implicit, DiscordRelationshipKind.unknown],
    );
  });

  test(
    'closing twice is what a repository shutdown does when retried',
    () async {
      final service = DiscordRelationshipService();

      await service.close();
      await service.close();

      expect(service.accept('READY', _ready()), isTrue);
    },
  );
}
