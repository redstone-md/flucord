import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/guild_management.dart';

void main() {
  group('calculatePositionDeltas', () {
    test('emits nothing when nothing moved', () {
      final items = [_item('a', 0), _item('b', 1), _item('c', 2)];
      expect(
        calculatePositionDeltas<_Item>(
          oldOrdering: items,
          newOrdering: items,
          idOf: (item) => item.id,
          positionOf: (item) => item.position,
          ascending: true,
        ),
        isEmpty,
      );
    });

    test('emits every row when the server numbered them all zero', () {
      // A guild really does come back like this, and comparing positions alone
      // would decide the drag was a no-op.
      final items = [_item('a', 0), _item('b', 0), _item('c', 0)];
      final moved = [items[2], items[0], items[1]];
      final deltas = calculatePositionDeltas<_Item>(
        oldOrdering: items,
        newOrdering: moved,
        idOf: (item) => item.id,
        positionOf: (item) => item.position,
        ascending: true,
      );
      expect(deltas, [
        (id: 'c', position: 0),
        (id: 'a', position: 1),
        (id: 'b', position: 2),
      ]);
    });

    test('skips an item whose index and position both already match', () {
      final before = [_item('a', 0), _item('b', 1), _item('c', 2)];
      final after = [before[0], before[2], before[1]];
      final deltas = calculatePositionDeltas<_Item>(
        oldOrdering: before,
        newOrdering: after,
        idOf: (item) => item.id,
        positionOf: (item) => item.position,
        ascending: true,
      );
      expect(deltas.map((delta) => delta.id), ['c', 'b']);
    });

    test('descending numbers from the end and reverses the result', () {
      final before = [_item('top', 2), _item('mid', 1), _item('low', 0)];
      final after = [before[1], before[0], before[2]];
      final deltas = calculatePositionDeltas<_Item>(
        oldOrdering: before,
        newOrdering: after,
        idOf: (item) => item.id,
        positionOf: (item) => item.position,
        ascending: false,
      );
      // Lowest first on the wire, because the array is reversed before it is
      // returned. The descending pass renumbers the whole ladder: an index and
      // a position run in opposite directions, so nothing looks untouched.
      expect(deltas, [
        (id: 'low', position: 0),
        (id: 'top', position: 1),
        (id: 'mid', position: 2),
      ]);
    });

    test('an item absent from the old ordering always moves', () {
      final deltas = calculatePositionDeltas<_Item>(
        oldOrdering: const [],
        newOrdering: [_item('new', 0)],
        idOf: (item) => item.id,
        positionOf: (item) => item.position,
        ascending: true,
      );
      expect(deltas, [(id: 'new', position: 0)]);
    });
  });

  group('roleReorderDeltas', () {
    test('drops @everyone from the result but not from the numbering', () {
      final before = [
        _role('admin', 3),
        _role('mod', 2),
        _role('member', 1),
        _role('guild-1', 0),
      ];
      final after = [before[1], before[0], before[2], before[3]];
      final deltas = roleReorderDeltas(before: before, after: after);
      expect(deltas.map((delta) => delta.id), isNot(contains('guild-1')));
      // `member` keeps position 1, not 0: @everyone still occupies zero even
      // though it is never sent.
      expect(deltas, [
        const RolePositionDelta(id: 'member', position: 1),
        const RolePositionDelta(id: 'admin', position: 2),
        const RolePositionDelta(id: 'mod', position: 3),
      ]);
      expect(deltas.first.toJson(), {'id': 'member', 'position': 1});
      expect(deltas.first, const RolePositionDelta(id: 'member', position: 1));
      expect(
        deltas.first.hashCode,
        const RolePositionDelta(id: 'member', position: 1).hashCode,
      );
      expect(deltas.first.toString(), contains('member'));
      expect(
        deltas.first == const RolePositionDelta(id: 'member', position: 9),
        isFalse,
      );
    });

    test('renumbers the whole ladder even when nothing was dragged', () {
      // Discord's roles page sends the complete array on every save; it does
      // not try to work out which rows the user actually touched.
      final roles = [_role('admin', 1), _role('guild-1', 0)];
      expect(roleReorderDeltas(before: roles, after: roles), [
        const RolePositionDelta(id: 'admin', position: 1),
      ]);
    });

    test('a guild with only @everyone sends nothing', () {
      final roles = [_role('guild-1', 0)];
      expect(roleReorderDeltas(before: roles, after: roles), isEmpty);
    });
  });

  group('channelReorderDeltas', () {
    test('numbers each visual bucket independently', () {
      final before = [
        _channel('cat', 0, GuildChannelType.category),
        _channel('text-a', 0, GuildChannelType.text),
        _channel('text-b', 1, GuildChannelType.text),
        _channel('voice-a', 0, GuildChannelType.voice),
      ];
      final after = [before[0], before[2], before[1], before[3]];
      final deltas = channelReorderDeltas(before: before, after: after);
      expect(deltas.map((delta) => delta.id), ['text-b', 'text-a']);
      expect(deltas.first.position, 0);
      expect(deltas.first.toJson(), {'id': 'text-b', 'position': 0});
    });

    test('merges a reparent into the moved channel and locks permissions', () {
      final before = [
        _channel('text-a', 0, GuildChannelType.text),
        _channel('text-b', 1, GuildChannelType.text),
      ];
      final after = [before[1], before[0]];
      final deltas = channelReorderDeltas(
        before: before,
        after: after,
        movedChannelId: 'text-b',
        newParentId: 'cat-2',
        lockPermissions: true,
      );
      final moved = deltas.firstWhere((delta) => delta.id == 'text-b');
      expect(moved.toJson(), {
        'id': 'text-b',
        'position': 0,
        'parent_id': 'cat-2',
        'lock_permissions': true,
      });
      expect(moved.hasParentId, isTrue);
      expect(moved.toString(), contains('cat-2'));
    });

    test('appends a bare reparent when the channel did not move', () {
      final channels = [_channel('text-a', 0, GuildChannelType.text)];
      final deltas = channelReorderDeltas(
        before: channels,
        after: channels,
        movedChannelId: 'text-a',
        newParentId: null,
      );
      expect(deltas.single.toJson(), {'id': 'text-a', 'parent_id': null});
      expect(deltas.single.position, isNull);
      expect(deltas.single.toString(), contains('text-a'));
    });

    test('an untouched list with no move sends nothing', () {
      final channels = [_channel('text-a', 0, GuildChannelType.text)];
      expect(channelReorderDeltas(before: channels, after: channels), isEmpty);
    });

    test('equality ignores nothing that matters on the wire', () {
      const left = ChannelPositionDelta(id: 'a', position: 1);
      const right = ChannelPositionDelta(id: 'a', position: 1);
      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left == const ChannelPositionDelta(id: 'a'), isFalse);
    });
  });

  test('a forum channel is bucketed with the text column', () {
    expect(GuildChannelType.forum.isTextLike, isTrue);
    expect(GuildChannelType.announcement.isTextLike, isTrue);
    expect(GuildChannelType.voice.isVoiceLike, isTrue);
    expect(GuildChannelType.category.isTextLike, isFalse);
    expect(GuildChannelType.fromWire(15), GuildChannelType.forum);
    expect(GuildChannelType.fromWire('2'), GuildChannelType.voice);
    expect(GuildChannelType.fromWire(99), isNull);
    expect(GuildChannelType.fromWire(null), isNull);
  });
}

final class _Item {
  const _Item(this.id, this.position);

  final String id;
  final int position;
}

_Item _item(String id, int position) => _Item(id, position);

GuildRole _role(String id, int position) => GuildRole(
  id: id,
  guildId: 'guild-1',
  name: id,
  position: position,
  permissions: BigInt.zero,
);

ChannelOrderEntry _channel(String id, int position, GuildChannelType type) =>
    ChannelOrderEntry(id: id, position: position, type: type);
