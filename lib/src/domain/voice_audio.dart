import 'dart:typed_data';

final class VoiceRemoteOpusFrame {
  VoiceRemoteOpusFrame({required this.userId, required Uint8List opus})
    : opus = Uint8List.fromList(opus);

  final String userId;
  final Uint8List opus;
}

final class VoiceRemotePcmFrame {
  VoiceRemotePcmFrame({required this.userId, required Int16List samples})
    : samples = Int16List.fromList(samples);

  final String userId;
  final Int16List samples;
}

abstract interface class VoiceAudioTransport {
  Stream<VoiceRemoteOpusFrame> get remoteAudio;

  void sendOpusFrame(Uint8List opusFrame);
  Future<void> finishSpeaking();
}

abstract interface class VoiceOpusEncoder {
  Uint8List encode(Int16List pcm);
  void dispose();
}

abstract interface class VoiceOpusDecoder {
  Int16List decode(Uint8List opusFrame);
  void dispose();
}

abstract interface class VoiceOpusCodecFactory {
  VoiceOpusEncoder createEncoder();
  VoiceOpusDecoder createDecoder();
}
