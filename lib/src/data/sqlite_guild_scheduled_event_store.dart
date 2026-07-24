import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/chat_models.dart';

final class SqliteGuildScheduledEventStore {
  const SqliteGuildScheduledEventStore(this._database);

  final Database _database;

  Future<List<GuildScheduledEvent>> readForSpace(String spaceId) async {
    final rows = await _database.query(
      'guild_scheduled_events',
      where: 'space_id = ?',
      whereArgs: [spaceId],
      orderBy: 'scheduled_start_time',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> replaceForSpace(
    String spaceId,
    List<GuildScheduledEvent> events,
  ) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'guild_scheduled_events',
        where: 'space_id = ?',
        whereArgs: [spaceId],
      );
      final batch = transaction.batch();
      for (final event in events.where((event) => event.spaceId == spaceId)) {
        batch.insert('guild_scheduled_events', _toRow(event));
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> write(GuildScheduledEvent event) => _database.insert(
    'guild_scheduled_events',
    _toRow(event),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> delete(String eventId) => _database.delete(
    'guild_scheduled_events',
    where: 'id = ?',
    whereArgs: [eventId],
  );

  static Map<String, Object?> _toRow(GuildScheduledEvent event) => {
    'id': event.id,
    'space_id': event.spaceId,
    'channel_id': event.channelId,
    'name': event.name,
    'description': event.description,
    'location': event.location,
    'scheduled_start_time': event.scheduledStartTime.toUtc().toIso8601String(),
    'scheduled_end_time': event.scheduledEndTime?.toUtc().toIso8601String(),
    'entity_type': event.entityType.index,
    'status': event.status.index,
    'interested_count': event.interestedCount,
  };

  static GuildScheduledEvent _fromRow(Map<String, Object?> row) =>
      GuildScheduledEvent(
        id: row['id']! as String,
        spaceId: row['space_id']! as String,
        channelId: row['channel_id'] as String?,
        name: row['name']! as String,
        description: row['description'] as String?,
        location: row['location'] as String?,
        scheduledStartTime: DateTime.parse(
          row['scheduled_start_time']! as String,
        ),
        scheduledEndTime: switch (row['scheduled_end_time']) {
          final String value => DateTime.parse(value),
          _ => null,
        },
        entityType:
            GuildScheduledEventEntityType.values[row['entity_type']! as int],
        status: GuildScheduledEventStatus.values[row['status']! as int],
        interestedCount: row['interested_count']! as int,
      );
}
