import 'dart:typed_data';

import '../../app_log.dart';
import 'discord_h264_depacketizer.dart';

/// Decrypts one whole picture for the room's group.
///
/// Bound to one sender by the caller, because a group key is per sender and
/// this piece sees pictures, not senders.
typedef VideoPictureGroupDecryptor = Uint8List Function(Uint8List picture);

/// Turns one sender's RTP payloads into whole pictures for a decoder.
///
/// The order of the two steps is fixed by what the sender did: it encrypts one
/// complete H.264 picture and only then cuts the result into packets. No single
/// packet is a whole ciphertext, so a receiver has to put the packets back
/// together first and decrypt the reassembled picture once. Decrypting each
/// packet as it lands cannot work, and it fails quietly, because every fragment
/// is dropped for want of a whole picture to authenticate.
///
/// Reassembly stays a pure RFC 6184 job in the H.264 packet reassembler. This
/// class keeps only the policy about when the decryptor runs, so either can be
/// tested alone. This one needs no socket and no group session: a fake decryptor
/// that rejects anything less than a whole picture is enough to prove the
/// boundary.
/// One decrypted picture and the schedule it travels with.
///
/// The RTP timestamp is what a pacer needs to know when the frame is due; the
/// bytes are what a decoder needs to know what to show.
final class DiscordPicture {
  const DiscordPicture({required this.bytes, required this.rtpTimestamp});

  /// The plaintext H.264 access unit, Annex B.
  final Uint8List bytes;

  /// The sender's picture timestamp, 90 kHz ticks (RFC 3550).
  final int rtpTimestamp;
}

final class DiscordVideoPictureReceiver {
  DiscordVideoPictureReceiver({
    VideoPictureGroupDecryptor? decryptor,
    DiscordH264Depacketizer? depacketizer,
    void Function()? onPictureLoss,
    DateTime Function()? now,
  }) : _decryptor = decryptor,
       _depacketizer = depacketizer ?? DiscordH264Depacketizer(),
       _onPictureLoss = onPictureLoss,
       _now = now ?? DateTime.now;

  final VideoPictureGroupDecryptor? _decryptor;
  final DiscordH264Depacketizer _depacketizer;

  /// Asked when pictures keep failing to open, at most once a second: a
  /// stream whose references were lost stays broken until a fresh keyframe
  /// starts it over, and only the sender can send one (RFC 4585).
  final void Function()? _onPictureLoss;
  final DateTime Function() _now;
  DateTime? _lastKeyframeAsk;

  /// Set when a picture was lost and cleared only by a real keyframe: in
  /// between, every picture that opens is drawn from broken references.
  bool _referencesBroken = false;
  int _keyframesRecovered = 0;

  /// Feeds one RTP payload in.
  ///
  /// Returns the plaintext access unit when [marker] closes a picture, or
  /// `null` while the picture is still arriving. A picture that will not
  /// decrypt is dropped whole rather than raised: a key that has not reached
  /// this client yet is ordinary at the start of a share, and the next picture
  /// usually decrypts. What it looks like from outside is packets arriving and
  /// no pictures coming out, which the viewer counts separately.
  DiscordPicture? accept(
    Uint8List payload, {
    required bool marker,
    int rtpTimestamp = 0,
  }) {
    // Temporary diagnostics for the live picture check: they sample the wire
    // shape and the group decrypt boundary, so a log answers whether pictures
    // arrive and why they fail to open. Remove once a picture is confirmed
    // live.
    if (_sampledPayloads < _sampleLimit) {
      _sampledPayloads++;
      _log(
        'payload #$_sampledPayloads (marker $marker): '
        'len ${payload.length} head ${_hex(payload, 16)}',
      );
    } else if (marker && _sampledCloses < 3) {
      _sampledCloses++;
      _log(
        'closing payload #$_sampledCloses: '
        'len ${payload.length} head ${_hex(payload, 16)}',
      );
    }
    final encrypted = _depacketizer.accept(payload, marker: marker);
    if (encrypted == null) return null;
    _pictures++;
    final opened = _openPicture(encrypted);
    if (opened == null) return null;
    return DiscordPicture(bytes: opened, rtpTimestamp: rtpTimestamp);
  }

  /// TEMP DIAGNOSTICS turned experiment (remove with the live-check code):
  /// the group decryptor authenticates the sender's exact bytes, so a
  /// reassembled picture that differs by a single byte fails. When the plain
  /// assembly fails, the variants test which shape the sender actually used,
  /// and the winning shape is remembered and applied first, so pictures draw
  /// while the diagnosis is still running.
  Uint8List? _openPicture(Uint8List encrypted) {
    final decryptor = _decryptor;
    if (decryptor == null) return encrypted;
    final order = _variantKnown
        ? [_preferredVariant, 0, 1, 2, 3]
        : const [0, 1, 2, 3];
    final tried = <int>[];
    Object? lastError;
    for (final variant in order) {
      if (tried.contains(variant)) continue;
      tried.add(variant);
      try {
        final plain = decryptor(_applyVariant(variant, encrypted));
        if (_pictures <= 3 || _pictures % 200 == 0) {
          _log(
            'picture #$_pictures decrypted with variant $variant: '
            'len ${encrypted.length}',
          );
        }
        if (variant != _preferredVariant) {
          _log('reassembly variant $variant wins, remembering it');
          _preferredVariant = variant;
          _variantKnown = true;
        }
        // A picture that decrypts is not a picture that draws: one built on
        // top of a lost one opens fine and comes out smeared. Only a real
        // keyframe proves the references are whole again, so the keyframe
        // ask keeps going until one arrives.
        if (_referencesBroken) {
          if (_carriesIdrSlice(plain)) {
            _referencesBroken = false;
            _keyframesRecovered++;
            if (_keyframesRecovered <= 3 || _keyframesRecovered % 10 == 0) {
              _log(
                'keyframe recovered the stream (recovery '
                '#$_keyframesRecovered, picture #$_pictures, '
                '${plain.length} bytes)',
              );
            }
          } else {
            _askForKeyframe();
            // Decoding this would draw mush built on a frame the decoder
            // never saw, and spend the decode budget the keyframe needs.
            // Held back until the keyframe arrives.
            return null;
          }
        }
        return plain;
      } on Object catch (error) {
        lastError = error;
      }
    }
    _decryptFailures++;
    if (_decryptFailures <= 3 || _decryptFailures % 200 == 0) {
      _log(
        'picture #$_pictures decrypt failed, no variant worked '
        '(failures $_decryptFailures): len ${encrypted.length} '
        'head ${_hex(encrypted, 16)} tail ${_hexTail(encrypted, 8)} '
        'magic ${_endsWithMagic(encrypted)} '
        'scs ${_startCodePositions(encrypted)} :: $lastError',
      );
    }
    // The picture that failed carried references, so every later one is
    // built on a frame the decoder never saw, even though it decrypts.
    _referencesBroken = true;
    _askForKeyframe();
    return null;
  }

  /// Marks the reference chain broken from the outside: a decoder that had
  /// to drop an access unit (a queue overflow) breaks the chain exactly like
  /// a lost picture does, even though every packet arrived. Everything after
  /// the break decodes against references that do not exist, which is what
  /// draws as smeared colour until a keyframe lands.
  void markReferencesBroken() {
    _referencesBroken = true;
    _askForKeyframe();
  }

  /// Asks the sender for a keyframe while the decoder's references are
  /// broken, at most once a second. Not tied to consecutive decrypt
  /// failures: the failure that broke the chain is often just one picture,
  /// and everything after it opens fine and still draws garbage.
  void _askForKeyframe() {
    final onPictureLoss = _onPictureLoss;
    if (onPictureLoss == null) return;
    final now = _now();
    final last = _lastKeyframeAsk;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastKeyframeAsk = now;
    onPictureLoss();
  }

  /// Whether the access unit carries an IDR slice, the only thing that
  /// restarts a decoder's references (ITU-T H.264 Table 7-1, nal_unit_type 5).
  /// A keyframe usually leads with parameter sets, so a few NALs are looked
  /// at, not just the first.
  static bool _carriesIdrSlice(Uint8List unit) {
    var index = 0;
    var nals = 0;
    while (index < unit.length && nals < 8) {
      final code = _startCodeLengthAt(unit, index);
      if (code > 0) {
        index += code;
        nals++;
        if (index < unit.length && (unit[index] & 0x1f) == 5) return true;
        continue;
      }
      // A unit with its start codes stripped begins on the NAL header.
      if (nals == 0 && (unit[index] & 0x1f) == 5) return true;
      index++;
    }
    return false;
  }

  int _preferredVariant = 0;
  bool _variantKnown = false;

  /// 0: as reassembled. 1: leading start code stripped. 2: every three-byte
  /// start code widened to four. 3: every start code removed.
  static Uint8List _applyVariant(int variant, Uint8List input) {
    switch (variant) {
      case 1:
        final leading = _startCodeLengthAt(input, 0);
        return leading > 0
            ? Uint8List.fromList(input.sublist(leading))
            : input;
      case 2:
        return _withWideStartCodes(input);
      case 3:
        return _withoutStartCodes(input);
      default:
        return input;
    }
  }

  static int _startCodeLengthAt(Uint8List bytes, int index) {
    if (index + 4 <= bytes.length &&
        bytes[index] == 0 &&
        bytes[index + 1] == 0 &&
        bytes[index + 2] == 0 &&
        bytes[index + 3] == 1) {
      return 4;
    }
    if (index + 3 <= bytes.length &&
        bytes[index] == 0 &&
        bytes[index + 1] == 0 &&
        bytes[index + 2] == 1) {
      return 3;
    }
    return 0;
  }

  static Uint8List _withWideStartCodes(Uint8List input) {
    // Most pictures carry no three-byte code at all: a scan that finds none
    // hands back what came in rather than paying for a copy per frame. A
    // three-byte code sitting inside a four-byte one does not count.
    var hasThreeByteCode = false;
    for (var index = 0; index + 3 <= input.length; index++) {
      if (input[index] == 0 &&
          input[index + 1] == 0 &&
          input[index + 2] == 1 &&
          (index == 0 || input[index - 1] != 0)) {
        hasThreeByteCode = true;
        break;
      }
    }
    if (!hasThreeByteCode) return input;
    final out = <int>[];
    var index = 0;
    while (index < input.length) {
      final length = _startCodeLengthAt(input, index);
      if (length == 4) {
        out.addAll(const [0, 0, 0, 1]);
        index += 4;
      } else if (length == 3) {
        out.addAll(const [0, 0, 0, 1]);
        index += 3;
      } else {
        out.add(input[index]);
        index++;
      }
    }
    return Uint8List.fromList(out);
  }

  static Uint8List _withoutStartCodes(Uint8List input) {
    final out = <int>[];
    var index = 0;
    while (index < input.length) {
      final length = _startCodeLengthAt(input, index);
      if (length > 0) {
        index += length;
      } else {
        out.add(input[index]);
        index++;
      }
    }
    return Uint8List.fromList(out);
  }

  static bool _endsWithMagic(Uint8List bytes) =>
      bytes.length >= 2 && bytes[bytes.length - 2] == 0xfa &&
      bytes[bytes.length - 1] == 0xfa;

  static String _startCodePositions(Uint8List bytes) {
    final found = <String>[];
    for (var index = 0;
        index < bytes.length - 2 && found.length < 6;
        index++) {
      final length = _startCodeLengthAt(bytes, index);
      if (length > 0) {
        found.add('$index($length)');
        index += length - 1;
      }
    }
    return found.isEmpty ? 'none' : found.join(' ');
  }

  int _pictures = 0;
  int _decryptFailures = 0;
  int _sampledPayloads = 0;
  int _sampledCloses = 0;
  static const _sampleLimit = 5;

  void _log(String message) =>
      AppLog.warning('stream', 'picture diagnostic: $message');

  static String _hex(Uint8List bytes, int count) => [
    for (var index = 0; index < bytes.length && index < count; index++)
      bytes[index].toRadixString(16).padLeft(2, '0'),
  ].join(' ');

  static String _hexTail(Uint8List bytes, int count) => [
    for (var index = bytes.length > count ? bytes.length - count : 0;
        index < bytes.length;
        index++)
      bytes[index].toRadixString(16).padLeft(2, '0'),
  ].join(' ');
}
