part of 'chat_models.dart';

enum GuildScheduledEventEntityType {
  stage(1),
  voice(2),
  external(3),
  unknown(0);

  const GuildScheduledEventEntityType(this.discordValue);

  /// Discord's own number. Carried on the type rather than mapped at each end
  /// so the reader and the writer cannot drift apart.
  final int discordValue;
}

enum GuildScheduledEventStatus {
  scheduled(1),
  active(2),
  completed(3),
  canceled(4),
  unknown(0);

  const GuildScheduledEventStatus(this.discordValue);

  final int discordValue;
}

final class GuildScheduledEvent {
  const GuildScheduledEvent({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.scheduledStartTime,
    required this.entityType,
    required this.status,
    this.channelId,
    this.description,
    this.location,
    this.scheduledEndTime,
    this.interestedCount = 0,
  });

  final String id;
  final String spaceId;
  final String name;
  final String? channelId;
  final String? description;
  final String? location;
  final DateTime scheduledStartTime;
  final DateTime? scheduledEndTime;
  final GuildScheduledEventEntityType entityType;
  final GuildScheduledEventStatus status;
  final int interestedCount;

  bool get isActive => status == GuildScheduledEventStatus.active;
  bool get isTerminal =>
      status == GuildScheduledEventStatus.completed ||
      status == GuildScheduledEventStatus.canceled;

  static int compareForDisplay(
    GuildScheduledEvent left,
    GuildScheduledEvent right,
  ) {
    if (left.isActive != right.isActive) return left.isActive ? -1 : 1;
    return left.scheduledStartTime.compareTo(right.scheduledStartTime);
  }

  GuildScheduledEvent copyWith({int? interestedCount}) => GuildScheduledEvent(
    id: id,
    spaceId: spaceId,
    name: name,
    channelId: channelId,
    description: description,
    location: location,
    scheduledStartTime: scheduledStartTime,
    scheduledEndTime: scheduledEndTime,
    entityType: entityType,
    status: status,
    interestedCount: interestedCount ?? this.interestedCount,
  );
}
