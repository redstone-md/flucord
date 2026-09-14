import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

abstract final class ChannelActivityPersistence {
  static Future<void> save(
    ChatRepository repository,
    ChatWorkspace? workspace,
    String channelId,
  ) async {
    final channel = workspace?.channelOrNull(channelId);
    if (channel == null) return;
    try {
      await repository.saveChannelActivity(channel);
    } catch (_) {
      // Activity persistence is best-effort and must not break live chat.
    }
  }
}
