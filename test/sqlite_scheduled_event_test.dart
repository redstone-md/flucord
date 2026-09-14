import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'replaces, updates, and deletes isolated guild event catalogs',
    () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);

      await cache.replaceGuildScheduledEvents('guild-1', [
        _event('event-old', 'guild-1', count: 3),
      ]);
      await cache.replaceGuildScheduledEvents('guild-2', [
        _event('event-other', 'guild-2', count: 5),
      ]);
      await cache.replaceGuildScheduledEvents('guild-1', [
        _event('event-new', 'guild-1', count: 8),
      ]);

      expect(
        (await cache.readGuildScheduledEvents('guild-1')).single.id,
        'event-new',
      );
      expect(
        (await cache.readGuildScheduledEvents('guild-2')).single.id,
        'event-other',
      );

      await cache.writeGuildScheduledEvent(
        _event('event-new', 'guild-1', count: 9),
      );
      expect(
        (await cache.readGuildScheduledEvents(
          'guild-1',
        )).single.interestedCount,
        9,
      );
      await cache.deleteGuildScheduledEvent('event-new');
      expect(await cache.readGuildScheduledEvents('guild-1'), isEmpty);
    },
  );
}

GuildScheduledEvent _event(String id, String spaceId, {required int count}) =>
    GuildScheduledEvent(
      id: id,
      spaceId: spaceId,
      name: 'Native review',
      location: 'Build room',
      scheduledStartTime: DateTime.utc(2026, 7, 24, 18),
      scheduledEndTime: DateTime.utc(2026, 7, 24, 19),
      entityType: GuildScheduledEventEntityType.external,
      status: GuildScheduledEventStatus.scheduled,
      interestedCount: count,
    );
