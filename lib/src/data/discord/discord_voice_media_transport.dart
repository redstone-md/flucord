import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import 'discord_rtp_packet.dart';
import 'discord_rtp_reorder_buffer.dart';

typedef DiscordDaveAudioEncryptor = Uint8List Function(Uint8List opusFrame);
typedef DiscordDaveAudioDecryptor =
    Uint8List Function(String userId, Uint8List encryptedFrame);
typedef DiscordAudioFrameSender = int Function(DiscordRtpFrame frame);
typedef DiscordSpeakingSender = void Function(bool enabled);
typedef DiscordVoiceUserLookup = String? Function(int ssrc);

final class DiscordVoiceMediaTransport implements VoiceAudioTransport {
  factory DiscordVoiceMediaTransport({
    required Stream<DiscordRtpFrame> incomingFrames,
    required DiscordDaveAudioEncryptor encryptDave,
    required DiscordDaveAudioDecryptor decryptDave,
    required DiscordAudioFrameSender sendFrame,
    required DiscordSpeakingSender sendSpeaking,
    required DiscordVoiceUserLookup userForSsrc,
  }) => DiscordVoiceMediaTransport._(
    incomingFrames,
    encryptDave,
    decryptDave,
    sendFrame,
    sendSpeaking,
    userForSsrc,
  );

  DiscordVoiceMediaTransport._(
    this._incomingFrames,
    this._encryptDave,
    this._decryptDave,
    this._sendFrame,
    this._sendSpeaking,
    this._userForSsrc,
  );

  static final Uint8List _opusSilence = Uint8List.fromList([0xf8, 0xff, 0xfe]);
  static const int _silenceFrameCount = 5;

  final Stream<DiscordRtpFrame> _incomingFrames;
  final DiscordDaveAudioEncryptor _encryptDave;
  final DiscordDaveAudioDecryptor _decryptDave;
  final DiscordAudioFrameSender _sendFrame;
  final DiscordSpeakingSender _sendSpeaking;
  final DiscordVoiceUserLookup _userForSsrc;
  final Map<int, _RemoteAudioState> _remoteStates = {};
  DiscordAudioRtpPacketizer? _packetizer;
  bool _daveEnabled = false;
  bool _speaking = false;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio =>
      _incomingFrames.expand(_decodeRemoteFrames);

  void configure({required int ssrc, required bool daveEnabled}) {
    _packetizer = DiscordAudioRtpPacketizer.secure(ssrc: ssrc);
    _daveEnabled = daveEnabled;
    _speaking = false;
    _remoteStates.clear();
  }

  void reset() {
    _packetizer = null;
    _daveEnabled = false;
    _speaking = false;
    _remoteStates.clear();
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    if (opusFrame.isEmpty) throw ArgumentError('Opus frame cannot be empty');
    final packetizer = _packetizer;
    if (packetizer == null) throw StateError('Voice media is not ready');
    final startsSpeaking = !_speaking;
    if (startsSpeaking) {
      _sendSpeaking(true);
      _speaking = true;
    }
    try {
      final payload = _daveEnabled ? _encryptDave(opusFrame) : opusFrame;
      final sent = _sendFrame(
        packetizer.packetize(payload, marker: startsSpeaking),
      );
      if (sent <= 0) throw StateError('Discord voice UDP packet was not sent');
    } catch (_) {
      if (startsSpeaking) {
        _speaking = false;
        _sendSpeaking(false);
      }
      rethrow;
    }
  }

  @override
  Future<void> finishSpeaking() async {
    if (!_speaking) return;
    try {
      for (var index = 0; index < _silenceFrameCount; index++) {
        sendOpusFrame(_opusSilence);
      }
    } finally {
      _speaking = false;
      _sendSpeaking(false);
    }
  }

  Iterable<VoiceRemoteOpusFrame> _decodeRemoteFrames(DiscordRtpFrame frame) {
    final userId = _userForSsrc(frame.header.ssrc);
    if (userId == null) return const [];
    final currentState = _remoteStates[frame.header.ssrc];
    final state = currentState == null || currentState.userId != userId
        ? (_remoteStates[frame.header.ssrc] = _RemoteAudioState(userId))
        : currentState;
    return [
      for (final orderedFrame in state.reorderBuffer.add(frame))
        _decodeRemoteFrame(userId, orderedFrame),
    ];
  }

  VoiceRemoteOpusFrame _decodeRemoteFrame(
    String userId,
    DiscordRtpFrame frame,
  ) {
    final encrypted = Uint8List.fromList(frame.payload);
    final opus = _daveEnabled ? _decryptDave(userId, encrypted) : encrypted;
    return VoiceRemoteOpusFrame(userId: userId, opus: opus);
  }
}

final class _RemoteAudioState {
  _RemoteAudioState(this.userId);

  final String userId;
  final DiscordRtpReorderBuffer reorderBuffer = DiscordRtpReorderBuffer();
}
