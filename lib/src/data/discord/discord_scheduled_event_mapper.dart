part of 'discord_mapper.dart';

extension DiscordScheduledEventMapper on DiscordMapper {
  GuildScheduledEvent? guildScheduledEvent(
    Map<String, Object?> payload, {
    String? fallbackSpaceId,
  }) {
    final id = payload['id'] as String?;
    final spaceId = payload['guild_id'] as String? ?? fallbackSpaceId;
    final name = payload['name'] as String?;
    final start = DateTime.tryParse(
      payload['scheduled_start_time'] as String? ?? '',
    );
    if (id == null || spaceId == null || name == null || start == null) {
      return null;
    }
    final metadata = payload['entity_metadata'];
    return GuildScheduledEvent(
      id: id,
      spaceId: spaceId,
      channelId: payload['channel_id'] as String?,
      name: name,
      description: payload['description'] as String?,
      location: metadata is Map ? metadata['location'] as String? : null,
      scheduledStartTime: start,
      scheduledEndTime: DateTime.tryParse(
        payload['scheduled_end_time'] as String? ?? '',
      ),
      entityType: switch (payload['entity_type']) {
        1 => GuildScheduledEventEntityType.stage,
        2 => GuildScheduledEventEntityType.voice,
        3 => GuildScheduledEventEntityType.external,
        _ => GuildScheduledEventEntityType.unknown,
      },
      status: switch (payload['status']) {
        1 => GuildScheduledEventStatus.scheduled,
        2 => GuildScheduledEventStatus.active,
        3 => GuildScheduledEventStatus.completed,
        4 => GuildScheduledEventStatus.canceled,
        _ => GuildScheduledEventStatus.unknown,
      },
      interestedCount: payload['user_count'] as int? ?? 0,
    );
  }
}
