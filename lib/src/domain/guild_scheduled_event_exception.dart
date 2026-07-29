part of 'chat_models.dart';

/// One occurrence of a repeating event that differs from the rule.
///
/// Discord calls these exceptions. An occurrence is either moved to another
/// time or called off, and the rest of the series carries on as the rule says.
final class GuildScheduledEventException {
  const GuildScheduledEventException({
    required this.id,
    required this.eventId,
    this.spaceId = '',
    this.scheduledStartTime,
    this.scheduledEndTime,
    this.isCanceled = false,
  });

  final String id;
  final String eventId;
  final String spaceId;

  /// When this occurrence happens instead, or null when only its cancellation
  /// changed — Discord sends one or the other, not both by default.
  final DateTime? scheduledStartTime;
  final DateTime? scheduledEndTime;

  /// This occurrence is called off. The series is not.
  final bool isCanceled;

  /// One line for a surface with room for one.
  String describe() {
    if (isCanceled) return 'One occurrence is cancelled';
    if (scheduledStartTime == null) return 'One occurrence differs';
    return 'One occurrence moved';
  }

  static GuildScheduledEventException? fromJson(Object? payload) {
    if (payload is! Map) return null;
    final fields = payload.cast<String, Object?>();
    final id = fields['event_exception_id'];
    final eventId = fields['event_id'];
    if (id is! String || id.isEmpty || eventId is! String || eventId.isEmpty) {
      return null;
    }
    return GuildScheduledEventException(
      id: id,
      eventId: eventId,
      spaceId: fields['guild_id'] is String
          ? fields['guild_id']! as String
          : '',
      scheduledStartTime: _time(fields['scheduled_start_time']),
      scheduledEndTime: _time(fields['scheduled_end_time']),
      isCanceled: fields['is_canceled'] == true,
    );
  }

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  @override
  bool operator ==(Object other) =>
      other is GuildScheduledEventException &&
      other.id == id &&
      other.eventId == eventId &&
      other.spaceId == spaceId &&
      other.scheduledStartTime == scheduledStartTime &&
      other.scheduledEndTime == scheduledEndTime &&
      other.isCanceled == isCanceled;

  @override
  int get hashCode => Object.hash(
    id,
    eventId,
    spaceId,
    scheduledStartTime,
    scheduledEndTime,
    isCanceled,
  );
}
