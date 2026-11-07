part of 'chat_models.dart';

/// The type every voice message file is sent and stored as.
const voiceMessageContentType = 'audio/ogg';

/// A finished recording on disk that has not been sent yet.
final class PendingVoiceMessage {
  PendingVoiceMessage({
    required this.name,
    required this.path,
    required this.size,
    required this.durationSecs,
    required this.waveform,
  }) {
    if (name.isEmpty || path.isEmpty || size <= 0) {
      throw ArgumentError('Voice message file metadata is invalid');
    }
    if (durationSecs <= 0 || waveform.isEmpty) {
      throw ArgumentError('Voice message audio metadata is invalid');
    }
  }

  final String name;
  final String path;
  final int size;
  final double durationSecs;
  final String waveform;

  /// The recording as the file a message uploads.
  PendingAttachment get attachment =>
      PendingAttachment(name: name, path: path, size: size);

  /// The voice message as the timeline draws it before Discord has it. The
  /// recording plays from the disk.
  ChatMessage asMessage({
    required String id,
    required String channelId,
    required String authorId,
    required DateTime sentAt,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    authorId: authorId,
    body: '',
    sentAt: sentAt,
    flags: DiscordMessageFlag.voiceMessage.bit,
    attachments: [
      MessageAttachment(
        id: '$id-voice',
        fileName: name,
        url: Uri.file(path).toString(),
        size: size,
        contentType: voiceMessageContentType,
        durationSecs: durationSecs,
        waveform: waveform,
      ),
    ],
  );
}
