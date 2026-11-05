import '../../domain/chat_models.dart';
import '../../domain/voice_message_recorder.dart';

/// The JSON body that posts [voiceMessage] as a voice message.
///
/// A bot sends the file in the same request as a form part, so it leaves
/// [uploadedFilename] out. A user account uploads the file first and names it
/// here with the `upload_filename` Discord gave for the upload slot.
Map<String, Object?> discordVoiceMessageBody(
  PendingVoiceMessage voiceMessage, {
  String? nonce,
  bool enforceNonce = false,
  String? uploadedFilename,
}) => {
  'flags': DiscordMessageFlag.voiceMessage.bit,
  'nonce': ?nonce,
  if (nonce != null) 'enforce_nonce': enforceNonce,
  'attachments': [
    {
      'id': 0,
      'filename': voiceMessage.name,
      'uploaded_filename': ?uploadedFilename,
      'duration_secs': voiceMessage.durationSecs,
      'waveform': voiceMessage.waveform,
    },
  ],
};
