part of 'discord_member_list_test.dart';

void _memberListStoreCases() {
  group('member list store', () {
    Map<String, Object?> member(String id) => {
      'user': {'id': id, 'username': 'user-$id'},
      'roles': const <String>[],
      'presence': {'status': 'online'},
    };

    Map<String, Object?> dispatch({
      required List<Map<String, Object?>> ops,
      required List<Map<String, Object?>> groups,
      int memberCount = 0,
      int onlineCount = 0,
      String listId = 'everyone',
    }) => {
      'guild_id': 'guild',
      'id': listId,
      'ops': ops,
      'groups': groups,
      'member_count': memberCount,
      'online_count': onlineCount,
    };

    test('lays a SYNC out across the flat header and member row space', () {
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: [
            {
              'op': 'SYNC',
              'range': [0, 3],
              'items': [
                {
                  'group': {'id': 'online', 'count': 2},
                },
                {'member': member('a')},
                {'member': member('b')},
                {
                  'group': {'id': 'offline', 'count': 0},
                },
              ],
            },
          ],
          groups: [
            {'id': 'online', 'count': 2},
            {'id': 'offline', 'count': 0},
          ],
          memberCount: 3,
          onlineCount: 2,
        ),
      )!;

      final list = DiscordMemberListStore().apply(update);

      expect(list.rows, [
        const GuildMemberListGroupRow(groupId: 'online', count: 2),
        const GuildMemberListMemberRow('a'),
        const GuildMemberListMemberRow('b'),
        const GuildMemberListGroupRow(groupId: 'offline', count: 0),
      ]);
      expect(list.groups.map((group) => group.index), [0, 3]);
      expect(list.memberCount, 3);
      expect(list.onlineCount, 2);
      expect(list.version, 1);
      expect(list.isLoaded, isTrue);
      expect(list.everyoneMentionSize, 2);
      expect(list.hereMentionSize, 2);
      expect(list.key, 'guild:everyone');
      expect(
        update.memberItems.map((item) => item.member!['user']),
        hasLength(2),
      );
    });

    test('applies insert, replace and delete in order', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 2],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 2},
                  },
                  {'member': member('a')},
                  {'member': member('b')},
                ],
              },
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      final list = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INSERT',
                'index': 1,
                'item': {'member': member('c')},
              },
              {
                'op': 'UPDATE',
                'index': 2,
                'item': {'member': member('d')},
              },
              {'op': 'DELETE', 'index': 3},
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      expect(list.rows, [
        const GuildMemberListGroupRow(groupId: 'online', count: 2),
        const GuildMemberListMemberRow('c'),
        const GuildMemberListMemberRow('d'),
      ]);
      expect(list.version, 2);
    });

    test('invalidate stops at the first hole', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 1],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 4},
                  },
                  {'member': member('a')},
                ],
              },
              {
                'op': 'UPDATE',
                'index': 4,
                'item': {'member': member('e')},
              },
            ],
            groups: [
              {'id': 'online', 'count': 4},
            ],
          ),
        )!,
      );

      final list = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INVALIDATE',
                'range': [0, 4],
              },
            ],
            groups: [
              {'id': 'online', 'count': 4},
            ],
          ),
        )!,
      );

      expect(list.rows[0], isNull);
      expect(list.rows[1], isNull);
      expect(list.rows[2], isNull);
      expect(list.rows[4], const GuildMemberListMemberRow('e'));
    });

    test('groups resize the row space after the ops', () {
      final store = DiscordMemberListStore();
      store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'SYNC',
                'range': [0, 2],
                'items': [
                  {
                    'group': {'id': 'online', 'count': 2},
                  },
                  {'member': member('a')},
                  {'member': member('b')},
                ],
              },
            ],
            groups: [
              {'id': 'online', 'count': 2},
            ],
          ),
        )!,
      );

      final shrunk = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 1},
            ],
          ),
        )!,
      );
      expect(shrunk.rows, hasLength(2));

      final grown = store.apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 3},
            ],
          ),
        )!,
      );
      expect(grown.rows, hasLength(4));
      expect(grown.rows.last, isNull);
    });

    test('tracks lists per guild and clears them', () {
      final store = DiscordMemberListStore();
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: const [],
          groups: [
            {'id': 'online', 'count': 0},
          ],
        ),
      )!;
      store.apply(update);

      expect(store.listFor('guild', 'everyone'), isNotNull);
      expect(store.lists, hasLength(1));
      store.clearGuild('other');
      expect(store.lists, hasLength(1));
      store.clearGuild('guild');
      expect(store.lists, isEmpty);

      store
        ..apply(update)
        ..clear();
      expect(store.lists, isEmpty);
    });

    test('ignores ops and payloads it cannot act on', () {
      final update = DiscordMemberListUpdate.fromDispatch({
        'guild_id': 'guild',
        'id': 'everyone',
        'ops': [
          {'op': 'CONTENT_INVENTORY'},
          {'op': 'SYNC', 'range': 'bad', 'items': <Object?>[]},
          {
            'op': 'SYNC',
            'range': [3, 1],
            'items': <Object?>[],
          },
          {
            'op': 'INVALIDATE',
            'range': [0],
          },
          {'op': 'INSERT', 'index': -1, 'item': <String, Object?>{}},
          {'op': 'UPDATE', 'index': 0, 'item': <String, Object?>{}},
          {'op': 'DELETE', 'index': 'x'},
          {'op': 42},
          {
            'op': 'SYNC',
            'range': [0, 1],
            'items': [
              {
                'member': {'user': 'not-an-object'},
              },
              {
                'group': {'count': 1},
              },
            ],
          },
        ],
        'groups': [
          {'count': 1},
          {'id': 'online', 'count': -5},
        ],
        'member_count': 'bad',
        'online_count': null,
      })!;

      final list = DiscordMemberListStore().apply(update);

      expect(update.ops, hasLength(1));
      expect(list.memberCount, 0);
      expect(list.onlineCount, 0);
      expect(list.groups.single.count, 0);
      expect(list.rows, hasLength(1));
      expect(update.memberItems, isEmpty);
    });

    test('rejects a dispatch without identifiers', () {
      expect(DiscordMemberListUpdate.fromDispatch(const {}), isNull);
      expect(
        DiscordMemberListUpdate.fromDispatch(const {'guild_id': 'guild'}),
        isNull,
      );
    });

    test('an out of range insert grows the row space', () {
      final list = DiscordMemberListStore().apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: [
              {
                'op': 'INSERT',
                'index': 3,
                'item': {'member': member('a')},
              },
            ],
            groups: const [],
          ),
        )!,
      );

      expect(list.rows, hasLength(4));
      expect(list.rows.last, const GuildMemberListMemberRow('a'));
      expect(list.rows.first, isNull);
    });

    test('a pending list reports that it has not loaded', () {
      final pending = GuildMemberList.pending(
        guildId: 'guild',
        listId: 'everyone',
      );

      expect(pending.isLoaded, isFalse);
      expect(pending.rows, isEmpty);
      expect(pending.toString(), contains('guild:everyone'));
      expect(
        const GuildMemberListGroupRow(groupId: 'online', count: 1).toString(),
        contains('online'),
      );
      expect(
        const GuildMemberListMemberRow('a').hashCode,
        const GuildMemberListMemberRow('a').hashCode,
      );
      expect(
        const GuildMemberListGroup(id: 'online', count: 1, index: 0),
        const GuildMemberListGroup(id: 'online', count: 1, index: 0),
      );
      expect(
        const GuildMemberListGroup(id: 'online', count: 1, index: 0).hashCode,
        const GuildMemberListGroup(id: 'online', count: 1, index: 0).hashCode,
      );
    });

    test('carries members out of insert and replace ops', () {
      final update = DiscordMemberListUpdate.fromDispatch(
        dispatch(
          ops: [
            {
              'op': 'INSERT',
              'index': 0,
              'item': {'member': member('a')},
            },
            {
              'op': 'UPDATE',
              'index': 0,
              'item': {'member': member('b')},
            },
            {
              'op': 'INSERT',
              'index': 1,
              'item': {
                'group': {'id': 'online', 'count': 1},
              },
            },
            {
              'op': 'INVALIDATE',
              'range': [0, 1],
            },
            {'op': 'DELETE', 'index': 1},
          ],
          groups: const [],
        ),
      )!;

      expect(
        update.memberItems.map(
          (item) => (item.row as GuildMemberListMemberRow).userId,
        ),
        ['a', 'b'],
      );
      expect(update.memberItems.first.presence, {'status': 'online'});
    });

    test('reuses a list when nothing is overridden', () {
      final list = GuildMemberList.pending(guildId: 'guild', listId: 'list');

      final copy = list.copyWith();

      expect(copy.rows, list.rows);
      expect(copy.groups, list.groups);
      expect(copy.memberCount, list.memberCount);
      expect(copy.onlineCount, list.onlineCount);
      expect(copy.version, list.version);
    });

    test('rows and overwrite bits expose value semantics', () {
      const group = GuildMemberListGroupRow(groupId: 'online', count: 2);

      expect(group.hashCode, group.hashCode);
      expect(
        group,
        isNot(const GuildMemberListGroupRow(groupId: 'x', count: 2)),
      );
      expect(const GuildMemberListMemberRow('a').toString(), contains('a'));
      expect(const GuildMemberListMemberRow('a'), isNot(group));

      final overwrite = DiscordPermissionOverwrite.fromJson(const {
        'id': 'role',
      })!;
      expect(overwrite.allow, BigInt.zero);
      expect(overwrite.deny, BigInt.zero);
      expect(overwrite.grants(DiscordMemberListId.viewChannel), isFalse);
    });

    test('offline members are excluded from the here mention size', () {
      final list = DiscordMemberListStore().apply(
        DiscordMemberListUpdate.fromDispatch(
          dispatch(
            ops: const [],
            groups: [
              {'id': 'online', 'count': 3},
              {'id': 'offline', 'count': 7},
            ],
          ),
        )!,
      );

      expect(list.everyoneMentionSize, 10);
      expect(list.hereMentionSize, 3);
    });
  });
}
