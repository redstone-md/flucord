import 'dart:async';
import 'dart:typed_data';

import '../app_log.dart';
import '../data/discord/discord_video_picture_receiver.dart';
import '../domain/video_decoder.dart';
import '../domain/voice_audio.dart';
import '../monotonic_clock.dart';
import 'stream_picture_pacer.dart';
import 'voice_audio_receiver.dart';

/// One RTP payload as it arrives from a stream connection.
final class IncomingVideoPacket {
  const IncomingVideoPacket({
    required this.payload,
    required this.marker,
    this.rtpTimestamp = 0,
  });

  final Uint8List payload;

  /// Whether this payload ends a picture.
  final bool marker;

  /// The sender's picture timestamp, 90 kHz ticks (RFC 3550). Zero means the
  /// caller has none, and the picture is then decoded as it lands rather than
  /// paced: a stream that never says when its frames are due cannot be
  /// buffered against its own bursts.
  final int rtpTimestamp;
}

/// The screen-share audio a session carries, and what decodes it (ADR-0004).
typedef WatchedSessionAudio = ({
  Stream<VoiceRemoteOpusFrame> frames,
  VoiceOpusDecoderFactory decoderFactory,

  /// Names this session's sound to the room's playback.
  String sourceId,
});

/// Counts that tell "the pictures never arrived" from "the decoder got
/// everything and drew nothing".
typedef WatchedSessionStats = ({
  int receivedPackets,

  /// Whole pictures handed to the decoder.
  int pictures,

  /// Pictures the decoder produced.
  int decodedFrames,
  int pacerOverflows,
});

/// Turns one watched session's packets into paced pictures and sound.
///
/// Everything between a packet and a decoded frame is this module's:
/// reassembly, group decryption once per picture (ADR-0005), the verdict that
/// the decoder's references are broken, the keyframe ask and its rate limit,
/// the pacer, the decoder's lifetime across suspension (ADR-0003), and the
/// session's audio receiver. It knows nothing about stream keys, rooms, or
/// Discord: the caller hands it packets and reads frames.
///
/// Decoding on or off is the suspension seam. Off lets go of the decoder, the
/// receiver and the pacer and keeps counting packets; on makes them fresh, so
/// half a picture from before the window went away is never decoded and the
/// first picture back is a keyframe.
final class WatchedSessionPipeline {
  WatchedSessionPipeline({
    required VideoDecoderService Function() decoderFactory,
    VideoPictureGroupDecryptor? groupDecryptor,
    WatchedSessionAudio? audio,
    void Function()? requestKeyframe,
    void Function()? onFirstPicture,
    Duration Function()? now,
    bool paced = true,
  }) : _decoderFactory = decoderFactory,
       _groupDecryptor = groupDecryptor,
       _audio = audio,
       _requestKeyframe = requestKeyframe,
       _onFirstPicture = onFirstPicture,
       _now = now ?? monotonicNow,
       _paced = paced {
    // Suspension keeps the audio receiver attached: sound plays whether or
    // not pictures are being drawn (ADR-0003).
    if (audio != null) {
      final receiver = VoiceAudioReceiver(
        decoderFactory: audio.decoderFactory,
        sourceId: audio.sourceId,
      );
      _audioReceiver = receiver;
      _audioErrors = receiver.errors.listen(
        (error) => _diagnose('screen-share audio: $error'),
      );
      unawaited(receiver.bind(audio.frames));
    }
  }

  final VideoDecoderService Function() _decoderFactory;
  final VideoPictureGroupDecryptor? _groupDecryptor;
  final WatchedSessionAudio? _audio;

  /// Asked while the decoder's references are broken, at most once a second:
  /// only a fresh keyframe from the sender starts the stream over (RFC 4585).
  final void Function()? _requestKeyframe;

  /// Told once, when the stream goes from arriving to showing.
  final void Function()? _onFirstPicture;
  final Duration Function() _now;

  /// Whether pictures wait for their slot or decode as they land. Off for
  /// camera tiles, which are small, few, and expected to be live.
  final bool _paced;

  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final StreamController<String> _audioEnded = StreamController.broadcast();

  VoiceAudioReceiver? _audioReceiver;
  StreamSubscription<Object>? _audioErrors;
  VideoDecoderService? _decoder;
  DiscordVideoPictureReceiver? _receiver;
  StreamPicturePacer? _pacer;
  StreamSubscription<DecodedVideoFrame>? _decoderFrames;
  StreamSubscription<int>? _decoderDrops;

  /// Decoders still opening. One let go meanwhile is stopped once its start
  /// has answered, not while it runs: a decoder whose handle lands after the
  /// stop would be left open.
  final Set<VideoDecoderService> _opening = {};

  /// Set when a picture was lost, dropped, or never decoded, and cleared only
  /// by an IDR: in between, every picture that opens is drawn from references
  /// the decoder does not have, which is what smears as colour.
  bool _referencesBroken = false;
  Duration? _lastKeyframeAsk;
  bool _closed = false;

  int _receivedPackets = 0;
  int _pictures = 0;
  int _decodedFrames = 0;
  int _pacerOverflows = 0;

  /// Pictures, in decode order, whichever decoder is behind them.
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  /// Decoded screen-share audio, tagged with the session's source id.
  Stream<VoiceRemotePcmFrame> get pcm =>
      _audioReceiver?.remotePcm ?? const Stream<VoiceRemotePcmFrame>.empty();

  /// The audio source id, once the session has closed and its sound with it.
  Stream<String> get audioEnded => _audioEnded.stream;

  WatchedSessionStats get stats => (
    receivedPackets: _receivedPackets,
    pictures: _pictures,
    decodedFrames: _decodedFrames,
    pacerOverflows: _pacerOverflows,
  );

  /// Feeds one packet in. Counted always; turned into pictures only while
  /// decoding is on.
  void accept(IncomingVideoPacket packet) {
    if (_closed) return;
    _receivedPackets++;
    final receiver = _receiver;
    final decoder = _decoder;
    if (receiver == null || decoder == null) return;
    final failuresBefore = receiver.decryptFailures;
    final picture = receiver.accept(
      packet.payload,
      marker: packet.marker,
      rtpTimestamp: packet.rtpTimestamp,
    );
    if (picture == null) {
      // A picture that would not open carried references, so every later one
      // is built on a frame the decoder never saw. Nothing is asked for yet:
      // a key that has not arrived is ordinary at the start of a stream, and
      // the next picture that opens says whether the chain is really broken.
      if (receiver.decryptFailures > failuresBefore) _referencesBroken = true;
      return;
    }
    if (_referencesBroken) {
      if (DiscordVideoPictureReceiver.carriesIdrSlice(picture.bytes)) {
        _referencesBroken = false;
      } else {
        // Decoding this would draw mush and spend the decode budget the
        // keyframe needs. Held back until one arrives.
        _askForKeyframe();
        return;
      }
    }
    _pictures++;
    final pacer = _pacer;
    if (pacer == null) {
      unawaited(decoder.submit(picture.bytes));
    } else {
      pacer.submit(picture.bytes, picture.rtpTimestamp);
    }
    if (_pictures == 1) _onFirstPicture?.call();
  }

  /// Turns decoding on or off. Throws when the decoder will not open; the
  /// session is then still receiving, and a later "on" is a clean attempt.
  Future<void> setDecoding(bool on) async {
    if (_closed) return;
    if (!on) {
      await _release();
      return;
    }
    if (_decoder != null) return;
    final decoder = _decoderFactory();
    // Installed before it has finished opening: a second "on" then finds it
    // rather than opening another, and a picture that closes meanwhile has
    // somewhere to go.
    _decoder = decoder;
    _receiver = DiscordVideoPictureReceiver(decryptor: _groupDecryptor);
    // Whatever the decoder had before is gone with it: the first picture it
    // draws has to be a keyframe.
    _referencesBroken = true;
    _decoderFrames = decoder.frames.listen((frame) {
      _decodedFrames++;
      if (_decodedFrames == 1 || _decodedFrames % 300 == 0) {
        _diagnose('decoder frames: $_decodedFrames (pictures $_pictures)');
      }
      if (!_frames.isClosed) _frames.add(frame);
    });
    _decoderDrops = decoder.droppedAccessUnits.listen((dropped) {
      // A dropped access unit breaks the chain just like a lost picture,
      // even though every packet arrived.
      _diagnose('decoder dropped an access unit ($dropped total)');
      _markReferencesBroken();
    });
    if (_paced) {
      _pacer = StreamPicturePacer(
        submit: (unit, rtpTimestamp) => unawaited(
          decoder.submit(
            unit,
            // The RTP clock runs at 90 kHz; the decoder wants microseconds.
            timestamp: Duration(microseconds: rtpTimestamp * 1000000 ~/ 90000),
          ),
        ),
        isKeyframe: DiscordVideoPictureReceiver.carriesIdrSlice,
        now: _now,
        onOverflow: () {
          _pacerOverflows++;
          if (_pacerOverflows <= 3 || _pacerOverflows % 20 == 0) {
            _diagnose('pacer overflow #$_pacerOverflows: queue dropped');
          }
          _markReferencesBroken();
        },
      );
    }
    _opening.add(decoder);
    try {
      await decoder.start();
    } on Object {
      // Nobody wants a decoder that was let go while it failed to open.
      if (!identical(_decoder, decoder)) return;
      _decoder = null;
      _receiver = null;
      _pacer?.dispose();
      _pacer = null;
      await _decoderFrames?.cancel();
      await _decoderDrops?.cancel();
      rethrow;
    } finally {
      _opening.remove(decoder);
    }
    // Let go while it was opening: turned off, or closed. Handed back here,
    // now that it is open enough to hand back.
    if (!identical(_decoder, decoder)) await decoder.stop();
  }

  /// Lets go of the decoder, the pacer and the audio in one step.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _release();
    await _audioErrors?.cancel();
    await _audioReceiver?.dispose();
    final audio = _audio;
    if (audio != null) _audioEnded.add(audio.sourceId);
    await _audioEnded.close();
    await _frames.close();
  }

  /// Lets go of what turns packets into pictures. The decoder is stopped
  /// first and synchronously, unless it is still opening; that one is
  /// handed back by [setDecoding] once its start answers.
  Future<void> _release() async {
    final decoder = _decoder;
    _decoder = null;
    _receiver = null;
    // Disposing flushes what the pacer holds into the decoder before it
    // stops, rather than dropping pictures that already arrived.
    _pacer?.dispose();
    _pacer = null;
    final stopping = _opening.contains(decoder) ? null : decoder?.stop();
    await _decoderFrames?.cancel();
    await _decoderDrops?.cancel();
    _decoderFrames = null;
    _decoderDrops = null;
    await stopping;
  }

  void _markReferencesBroken() {
    _referencesBroken = true;
    _askForKeyframe();
  }

  void _askForKeyframe() {
    final ask = _requestKeyframe;
    if (ask == null) return;
    final now = _now();
    final last = _lastKeyframeAsk;
    if (last != null && now - last < const Duration(seconds: 1)) return;
    _lastKeyframeAsk = now;
    ask();
  }

  void _diagnose(String what) => AppLog.warning('stream', what);
}
