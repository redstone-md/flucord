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
      // Read through the codes the types carry, so the reader and the writer
      // cannot disagree about what a 3 means.
      entityType: GuildScheduledEventEntityType.values.firstWhere(
        (value) => value.discordValue == payload['entity_type'],
        orElse: () => GuildScheduledEventEntityType.unknown,
      ),
      status: GuildScheduledEventStatus.values.firstWhere(
        (value) => value.discordValue == payload['status'],
        orElse: () => GuildScheduledEventStatus.unknown,
      ),
      interestedCount: payload['user_count'] as int? ?? 0,
      coverImageHash: payload['image'] as String?,
      recurrence: EventRecurrenceRule.fromJson(payload['recurrence_rule']),
      exceptions: [
        for (final raw in switch (payload['guild_scheduled_event_exceptions']) {
          final List entries => entries,
          _ => const [],
        })
          ?GuildScheduledEventException.fromJson(raw),
      ],
    );
  }
}
