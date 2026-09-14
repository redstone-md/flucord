import 'chat_models.dart';
import 'voice_message_recorder.dart';

abstract interface class VoiceMessageRepository {
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
  });
}
