import 'package:flucord/src/domain/guild_folders.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server list the rail draws from the stored `guild_folders`, and how
/// each drop on the rail changes it.
void main() {
  // [a] [folder 7: b, c] [d]
  final rail = GuildRail.arrange(
    [
      GuildFolder.lone('a'),
      const GuildFolder(guildIds: ['b', 'c'], id: 7, name: 'Games'),
      GuildFolder.lone('d'),
    ],
    ['a', 'b', 'c', 'd'],
  );

  /// Each entry as its servers, with a folder's id in front.
  List<Object> shape(GuildRail rail) => [
    for (final entry in rail.entries)
      entry.id == null ? entry.guildIds.single : [entry.id, ...entry.guildIds],
  ];

  test('puts servers the settings do not list on top, and drops left ones', () {
    final arranged = GuildRail.arrange(
      [
        const GuildFolder(guildIds: ['b', 'gone'], id: 7),
        const GuildFolder(guildIds: ['gone-too'], id: 8),
        GuildFolder.lone('a'),
      ],
      ['a', 'b', 'new'],
    );

    expect(shape(arranged), [
      'new',
      [7, 'b'],
      'a',
    ]);
  });

  test('moves a server down the top level, before the entry it lands on', () {
    // Index 2 is d, counted with a still in its place.
    final moved = rail.drop(const DraggedGuild('a'), const RailDropAt(2));

    expect(shape(moved), [
      [7, 'b', 'c'],
      'a',
      'd',
    ]);
  });

  test('moves a server into a folder, before the one it lands on', () {
    final moved = rail.drop(
      const DraggedGuild('d'),
      const RailDropAt(1, folderId: 7),
    );

    expect(shape(moved), [
      'a',
      [7, 'b', 'd', 'c'],
    ]);
  });

  test('takes a server out of a folder, keeping the folder', () {
    final moved = rail.drop(const DraggedGuild('b'), const RailDropAt(0));

    expect(shape(moved), [
      'b',
      'a',
      [7, 'c'],
      'd',
    ]);
    expect(moved.entries[2].name, 'Games');
  });

  test('reorders the servers inside a folder', () {
    final moved = rail.drop(
      const DraggedGuild('b'),
      const RailDropAt(2, folderId: 7),
    );

    expect(shape(moved), [
      'a',
      [7, 'c', 'b'],
      'd',
    ]);
  });

  test('a folder emptied by a drag goes away', () {
    final moved = rail
        .drop(const DraggedGuild('b'), const RailDropAt(0))
        .drop(const DraggedGuild('c'), const RailDropAt(0));

    expect(shape(moved), ['c', 'b', 'a', 'd']);
  });

  test('dropping a server from a folder on a lone one makes a new folder', () {
    final moved = rail.drop(
      const DraggedGuild('c'),
      const RailDropOnto('d'),
      newFolderId: () => 9,
    );

    expect(shape(moved), [
      'a',
      [7, 'b'],
      [9, 'd', 'c'],
    ]);
  });

  test('moves a folder, but never into another folder', () {
    final moved = rail.drop(const DraggedFolder(7), const RailDropAt(0));

    expect(shape(moved), [
      [7, 'b', 'c'],
      'a',
      'd',
    ]);
    expect(
      rail.drop(const DraggedFolder(7), const RailDropOnto('a')),
      same(rail),
    );
    expect(
      rail.drop(const DraggedFolder(7), const RailDropAt(0, folderId: 7)),
      same(rail),
    );
  });

  test('renames and recolours a folder; an empty name clears it', () {
    final edited = rail.editFolder(7, name: '  ', colour: 0xeb459e);

    expect(edited.entries[1].name, isNull);
    expect(edited.entries[1].colour, 0xeb459e);
    expect(edited.entries[1].guildIds, ['b', 'c']);
  });
}
