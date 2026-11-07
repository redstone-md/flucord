import 'chat_models.dart';
import 'voice_message_recorder.dart';

abstract interface class VoiceMessageRepository {
  /// Sends [voiceMessage] under [nonce]. A retry passes the same nonce, so
  /// Discord answers with the first message if that one did arrive.
  /// [onUploadProgress] hears the recording's upload, from 0 to 1.
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
    required String nonce,
    UploadProgressListener? onUploadProgress,
  });
}
