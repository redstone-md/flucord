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
}
