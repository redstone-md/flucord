import 'dart:typed_data';

import '../../app_log.dart';
import 'discord_h264_depacketizer.dart';

/// Decrypts one whole picture for the room's group.
///
/// Bound to one sender by the caller, because a group key is per sender and
/// this piece sees pictures, not senders.
typedef VideoPictureGroupDecryptor = Uint8List Function(Uint8List picture);

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

/// Turns one sender's RTP payloads into whole pictures for a decoder.
///
/// The order of the two steps is fixed by what the sender did: it encrypts one
/// complete H.264 picture and only then cuts the result into packets. No single
/// packet is a whole ciphertext, so a receiver has to put the packets back
/// together first and decrypt the reassembled picture once. Decrypting each
/// packet as it lands cannot work, and it fails quietly, because every fragment
/// is dropped for want of a whole picture to authenticate (ADR-0005).
///
/// Reassembly stays a pure RFC 6184 job in the H.264 depacketizer, which
/// rebuilds the picture with the four-byte start codes the sender encrypted.
/// This class keeps only the policy about when the decryptor runs, so either
/// can be tested alone: a fake decryptor that rejects anything less than a
/// whole picture is enough to prove the boundary.
final class DiscordVideoPictureReceiver {
  DiscordVideoPictureReceiver({
    VideoPictureGroupDecryptor? decryptor,
    DiscordH264Depacketizer? depacketizer,
  }) : _decryptor = decryptor,
       _depacketizer = depacketizer ?? DiscordH264Depacketizer();

  final VideoPictureGroupDecryptor? _decryptor;
  final DiscordH264Depacketizer _depacketizer;
  int _decryptFailures = 0;

  /// How many whole pictures would not decrypt. Each one carried references,
  /// so whoever feeds the decoder reads this to know the chain is broken.
  int get decryptFailures => _decryptFailures;

  /// Feeds one RTP payload in.
  ///
  /// Returns the plaintext access unit when [marker] closes a picture, or
  /// `null` while the picture is still arriving. A picture that will not
  /// decrypt is dropped whole rather than raised: a key that has not reached
  /// this client yet is ordinary at the start of a share, and the next picture
  /// usually decrypts. What it looks like from outside is packets arriving and
  /// no pictures coming out, which the caller counts separately.
  DiscordPicture? accept(
    Uint8List payload, {
    required bool marker,
    int rtpTimestamp = 0,
  }) {
    final encrypted = _depacketizer.accept(payload, marker: marker);
    if (encrypted == null) return null;
    final decryptor = _decryptor;
    if (decryptor == null) {
      return DiscordPicture(bytes: encrypted, rtpTimestamp: rtpTimestamp);
    }
    try {
      return DiscordPicture(
        bytes: decryptor(encrypted),
        rtpTimestamp: rtpTimestamp,
      );
    } on Object catch (error) {
      _decryptFailures++;
      if (_decryptFailures <= 3 || _decryptFailures % 200 == 0) {
        AppLog.warning(
          'stream',
          'picture would not decrypt (failure #$_decryptFailures, '
              '${encrypted.length} bytes): $error',
        );
      }
      return null;
    }
  }

  /// Whether the access unit carries an IDR slice, the only thing that
  /// restarts a decoder's references (ITU-T H.264 Table 7-1, nal_unit_type 5).
  /// A keyframe usually leads with parameter sets, so a few NALs are looked
  /// at, not just the first.
  static bool carriesIdrSlice(Uint8List unit) {
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
}
