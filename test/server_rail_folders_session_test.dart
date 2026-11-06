import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

/// Server folders and the server order, which Discord keeps in the
/// `guild_folders` group of the account's settings.
void main() {
  const settingsPath = '/api/v9/users/@me/settings-proto/1';
  const forge = SessionHarness.guildId;
  const harbour = '200000000000000002';
  const garden = '200000000000000003';
  const gamesFolder = 100000000000000007;

  Finder space(String id) => find.byKey(ValueKey('space-$id'));
  final folder = find.byKey(const ValueKey('space-folder-$gamesFolder'));

  Map<String, Object?> ready(List<_Entry> entries, {int dataVersion = 4}) =>
      SessionHarness.defaultReady()
        ..['guilds'] = [
          for (final (id, name) in [
            (forge, 'The Forge'),
            (harbour, 'Harbour'),
            (garden, 'Garden'),
          ])
            rawGuild(
              id: id,
              name: name,
              channels: [
                rawChannel(
                  id: id == forge
                      ? SessionHarness.channelId
                      : '40000000000000000${id.substring(17)}',
                  name: 'general',
                ),
              ],
            ),
        ]
        ..['user_settings_proto'] = _settings(entries, dataVersion);

  Iterable<RecordedRequest> saves(SessionHarness session) => session
      .transport
      .requests
      .where((r) => r.method == 'PATCH' && r.uri.path == settingsPath);

  void echoSaves(FakeDiscordTransport transport) => transport.on(
    'PATCH',
    settingsPath,
    (request) => jsonResponse({
      'settings': (request.json! as Map<String, Object?>)['settings'],
    }),
  );

  /// Drags the tile [from] and lets go over [to], shifted by [by] from its
  /// centre, the way a mouse does.
  Future<void> drag(
    WidgetTester tester,
    SessionHarness session,
    Finder from,
    Finder to, {
    Offset by = Offset.zero,
  }) async {
    final mouse = await tester.startGesture(
      tester.getCenter(from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveBy(const Offset(0, 12));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(to) + by);
    await tester.pump();
    await mouse.up();
    await session.settle();
  }

  testSession(
    'shows the stored folders and order, with a folder closed until opened',
    (tester, session) async {
      expect(folder, findsOneWidget);
      expect(space(harbour), findsNothing);
      expect(space(garden), findsNothing);
      // The folder is stored above the Forge, so it is drawn above it.
      expect(
        tester.getCenter(folder).dy,
        lessThan(tester.getCenter(space(forge)).dy),
      );

      await tester.tap(folder);
      await session.settle();

      expect(space(harbour), findsOneWidget);
      expect(
        tester.getCenter(space(harbour)).dy,
        lessThan(tester.getCenter(space(garden)).dy),
      );
    },
    ready: ready([
      _Entry.folder(gamesFolder, [harbour, garden], name: 'Games'),
      _Entry.lone(forge),
    ]),
  );

  testSession(
    'dropping a server on another makes a folder and saves it',
    (tester, session) async {
      await drag(tester, session, space(harbour), space(garden));

      final save = saves(session).single;
      final body = save.json! as Map<String, Object?>;
      // Composed against the version READY carried, so Discord refuses it
      // if another device wrote in between.
      expect(body['required_data_version'], 4);
      final saved = _savedEntries(body['settings']! as String);
      expect(saved.map((entry) => entry.guildIds), [
        [forge],
        [garden, harbour],
      ]);
      expect(saved.first.id, isNull);
      expect(saved.last.id, isNotNull);
      // The rail draws the new folder at once, closed.
      expect(
        find.byKey(ValueKey('space-folder-${saved.last.id}')),
        findsOneWidget,
      );
      expect(space(harbour), findsNothing);
    },
    ready: ready([
      _Entry.lone(forge),
      _Entry.lone(garden),
      _Entry.lone(harbour),
    ]),
    routes: echoSaves,
    platform: TargetPlatform.windows,
  );

  testSession(
    'dragging a server out of an open folder saves it outside',
    (tester, session) async {
      await tester.tap(folder);
      await session.settle();

      // Over the top edge of the Forge, which places it just above.
      await drag(
        tester,
        session,
        space(harbour),
        space(forge),
        by: const Offset(0, -16),
      );

      final saved = _savedEntries(
        (saves(session).single.json! as Map<String, Object?>)['settings']!
            as String,
      );
      expect(saved.map((entry) => entry.guildIds), [
        [garden],
        [harbour],
        [forge],
      ]);
      expect(saved.map((entry) => entry.id), [gamesFolder, null, null]);
    },
    ready: ready([
      _Entry.folder(gamesFolder, [harbour, garden]),
      _Entry.lone(forge),
    ]),
    routes: echoSaves,
    platform: TargetPlatform.windows,
  );

  testSession(
    'a folder made on another device appears without a restart',
    (tester, session) async {
      expect(folder, findsNothing);

      await session.dispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {
          'type': 1,
          'proto': _settings([
            _Entry.lone(forge),
            _Entry.folder(gamesFolder, [garden, harbour]),
          ], 5),
        },
        'partial': true,
      });

      expect(folder, findsOneWidget);
      expect(space(garden), findsNothing);
    },
    ready: ready([
      _Entry.lone(forge),
      _Entry.lone(garden),
      _Entry.lone(harbour),
    ]),
  );

  testSession(
    'Folder settings renames and recolours a folder, and saves both',
    (tester, session) async {
      final mouse = await tester.startGesture(
        tester.getCenter(folder),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('folder-settings')));
      await session.settle();

      await tester.enterText(find.byKey(const ValueKey('folder-name')), 'Play');
      await tester.tap(find.byKey(const ValueKey('folder-colour-eb459e')));
      await tester.tap(find.byKey(const ValueKey('folder-save')));
      await session.settle();

      final saved = _savedEntries(
        (saves(session).single.json! as Map<String, Object?>)['settings']!
            as String,
      );
      expect(saved.single.id, gamesFolder);
      expect(saved.single.name, 'Play');
      expect(saved.single.colour, 0xeb459e);
      expect(find.byTooltip('Play'), findsOneWidget);
    },
    ready: ready([
      _Entry.folder(gamesFolder, [forge, harbour, garden], name: 'Games'),
    ]),
    routes: echoSaves,
    platform: TargetPlatform.windows,
  );
}

/// The folders a settings write stores, as the test wrote them.
List<_Entry> _savedEntries(String settings) {
  final group = DiscordUserSettingsProto.decodeRoot(
    settings,
  ).messageAt(PreloadedUserSettingsField.guildFolders)!;
  return [
    for (final folder in group.messagesAt(GuildFoldersField.folders))
      _Entry(
        id: folder.intWrapperAt(GuildFolderField.id),
        guildIds: [
          for (final id in folder.fixed64ListAt(GuildFolderField.guildIds))
            '$id',
        ],
        name: folder.stringWrapperAt(GuildFolderField.name),
        colour: folder.intWrapperAt(GuildFolderField.colour),
      ),
  ];
}

/// One stored entry of `guild_folders`: a folder when [id] is set.
final class _Entry {
  _Entry({required this.guildIds, this.id, this.name, this.colour});
  _Entry.folder(int this.id, this.guildIds, {this.name}) : colour = null;
  _Entry.lone(String guildId) : this(guildIds: [guildId]);

  final int? id;
  final List<String> guildIds;
  final String? name;
  final int? colour;
}

String _settings(List<_Entry> entries, int dataVersion) {
  final folders = ProtoMessage();
  for (final entry in entries) {
    final message = ProtoMessage()
      ..setFixed64List(
        GuildFolderField.guildIds,
        entry.guildIds.map(int.parse),
      );
    if (entry.id case final id?) message.setIntWrapper(GuildFolderField.id, id);
    if (entry.name case final name?) {
      message.setStringWrapper(GuildFolderField.name, name);
    }
    if (entry.colour case final colour?) {
      message.setIntWrapper(GuildFolderField.colour, colour);
    }
    folders.addMessage(GuildFoldersField.folders, message);
  }
  return DiscordUserSettingsProto.encodeBase64(
    (ProtoMessage()
          ..setMessage(
            PreloadedUserSettingsField.versions,
            ProtoMessage()..setVarint(VersionsField.dataVersion, dataVersion),
          )
          ..setMessage(PreloadedUserSettingsField.guildFolders, folders))
        .encode(),
  );
}
