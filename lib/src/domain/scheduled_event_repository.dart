import 'chat_models.dart';

abstract interface class ScheduledEventRepository {
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId);

  /// Says whether this account is interested in an event.
  ///
  /// Discord spells the two answers as one route with a body and the same
  /// route with none: interested is a `PUT` carrying the response, and taking
  /// it back is a `DELETE`. [exceptionId] names one occurrence of a recurring
  /// event, and is omitted for an event that happens once.
  ///
  /// Returns whether Discord accepted it. A refusal is an answer — an event
  /// that has already ended cannot be RSVPed to — not a fault.
  Future<bool> setEventInterest({
    required String spaceId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  });

  /// Creates an event. Returns it as the server stored it, so the surface
  /// shows what Discord actually recorded rather than what was typed.
  Future<GuildScheduledEvent?> createScheduledEvent({
    required String spaceId,
    required GuildScheduledEventDraft draft,
  });

  /// Applies a partial edit.
  Future<GuildScheduledEvent?> editScheduledEvent({
    required String spaceId,
    required String eventId,
    required GuildScheduledEventEdit edit,
  });

  /// Who said they are interested, newest first as Discord returns them.
  ///
  /// Capped rather than paged: the surface shows who is coming, and a list
  /// long enough to need paging is a list nobody reads to the end of.
  Future<List<GuildScheduledEventAttendee>> loadEventAttendees({
    required String spaceId,
    required String eventId,
    int limit = 100,
  });

  /// Deletes an event outright. Cancelling one is an edit of its status, and
  /// the two are deliberately not the same call.
  Future<bool> deleteScheduledEvent({
    required String spaceId,
    required String eventId,
  });
}
