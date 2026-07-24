import 'chat_models.dart';

abstract interface class ScheduledEventRepository {
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId);
}
