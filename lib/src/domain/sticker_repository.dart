import 'chat_models.dart';

abstract interface class StickerRepository {
  Future<ChatMessage> sendStickers({
    required String channelId,
    required String authorId,
    required List<String> stickerIds,
  });
}
