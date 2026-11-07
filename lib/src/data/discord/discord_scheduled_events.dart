import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';

/// A server's scheduled events, the same on the bot and desktop transports.
///
/// A read goes through the cache, so a server read once still shows its events
/// offline. The gateway dispatches about events fold into the cache and are
/// announced, which is how an RSVP's new count reaches the screen.
final class DiscordScheduledEvents {
  DiscordScheduledEvents(this._cache, this._mapper, this._publish);

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final void Function(ChatRepositoryEvent event) _publish;

  /// The events [fetch] reads for [spaceId], kept in the cache. When the read
  /// fails, the cached events stand in, if there are any.
  Future<List<GuildScheduledEvent>> load(
    String spaceId,
    Future<List<Map<String, Object?>>> Function() fetch,
  ) async {
    try {
      final events = [
        for (final payload in await fetch())
          ?_mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId),
      ]..sort(GuildScheduledEvent.compareForDisplay);
      await _cache.replaceGuildScheduledEvents(spaceId, events);
      return events;
    } catch (_) {
      final cached = await _cache.readGuildScheduledEvents(spaceId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// Folds one `GUILD_SCHEDULED_EVENT_*` dispatch in. Others are ignored.
  Future<void> apply(DiscordGatewayDispatch event) async {
    switch (event.name) {
      case 'GUILD_SCHEDULED_EVENT_CREATE' ||
          'GUILD_SCHEDULED_EVENT_UPDATE' ||
          'GUILD_SCHEDULED_EVENT_DELETE' ||
          'GUILD_SCHEDULED_EVENT_USER_ADD' ||
          'GUILD_SCHEDULED_EVENT_USER_REMOVE':
        await _applyEvent(event);
      case 'GUILD_SCHEDULED_EVENT_EXCEPTION_CREATE' ||
          'GUILD_SCHEDULED_EVENT_EXCEPTION_UPDATE' ||
          'GUILD_SCHEDULED_EVENT_EXCEPTION_DELETE' ||
          'GUILD_SCHEDULED_EVENT_EXCEPTIONS_DELETE':
        await _applyException(event);
    }
  }

  Future<void> _applyEvent(DiscordGatewayDispatch event) async {
    final data = event.data;
    final spaceId = data['guild_id'] as String?;
    final eventId = (data['guild_scheduled_event_id'] ?? data['id']) as String?;
    if (spaceId == null || eventId == null) return;
    switch (event.name) {
      case 'GUILD_SCHEDULED_EVENT_CREATE' || 'GUILD_SCHEDULED_EVENT_UPDATE':
        final mapped = _mapper.guildScheduledEvent(data);
        if (mapped == null) return;
        await _writeAndPublish(mapped);
      case 'GUILD_SCHEDULED_EVENT_DELETE':
        await _cache.deleteGuildScheduledEvent(eventId);
        _publish(
          GuildScheduledEventDeletedEvent(spaceId: spaceId, eventId: eventId),
        );
      case 'GUILD_SCHEDULED_EVENT_USER_ADD' ||
          'GUILD_SCHEDULED_EVENT_USER_REMOVE':
        final current = await _cached(spaceId, eventId);
        if (current == null) return;
        final delta = event.name.endsWith('ADD') ? 1 : -1;
        final nextCount = current.interestedCount + delta;
        await _writeAndPublish(
          current.copyWith(interestedCount: nextCount < 0 ? 0 : nextCount),
        );
    }
  }

  /// Folds a change to one occurrence of a repeating event in.
  ///
  /// Discord sends these separately from the event, and the plural delete puts
  /// a whole series back to its rule at once. An event not in the cache is
  /// left alone: inventing a row for it would show an event with no name.
  Future<void> _applyException(DiscordGatewayDispatch event) async {
    final data = event.data;
    final exception = GuildScheduledEventException.fromJson(
      data['guild_scheduled_event_exception'] ?? data,
    );
    final spaceId = (data['guild_id'] ?? exception?.spaceId) as String? ?? '';
    final eventId =
        (data['guild_scheduled_event_id'] ??
                data['event_id'] ??
                exception?.eventId)
            as String? ??
        '';
    if (spaceId.isEmpty || eventId.isEmpty) return;
    final current = await _cached(spaceId, eventId);
    if (current == null) return;
    final next = switch (event.name) {
      'GUILD_SCHEDULED_EVENT_EXCEPTION_CREATE' ||
      'GUILD_SCHEDULED_EVENT_EXCEPTION_UPDATE' =>
        exception == null ? null : current.withException(exception),
      'GUILD_SCHEDULED_EVENT_EXCEPTION_DELETE' =>
        exception == null ? null : current.withoutException(exception.id),
      // The plural form clears every exception on the event at once.
      _ => current.withoutExceptions(),
    };
    if (next == null) return;
    await _writeAndPublish(next);
  }

  Future<GuildScheduledEvent?> _cached(String spaceId, String eventId) async {
    final cached = await _cache.readGuildScheduledEvents(spaceId);
    return cached.where((item) => item.id == eventId).firstOrNull;
  }

  Future<void> _writeAndPublish(GuildScheduledEvent event) async {
    await _cache.writeGuildScheduledEvent(event);
    _publish(GuildScheduledEventUpsertedEvent(event));
  }
}
