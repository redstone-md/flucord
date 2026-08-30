import 'dart:typed_data';

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
/// Reassembly stays a pure RFC 6184 job inside the depacketiser and this class
/// keeps only the policy about when the decryptor runs, so either can be tested
/// alone. This one needs no socket and no group session: a fake decryptor that
/// rejects anything less than a whole picture is enough to prove the boundary.
final class DiscordVideoPictureReceiver {
  DiscordVideoPictureReceiver({
    VideoPictureGroupDecryptor? decryptor,
    DiscordH264Depacketizer? depacketizer,
  }) : _decryptor = decryptor,
       _depacketizer = depacketizer ?? DiscordH264Depacketizer();

  final VideoPictureGroupDecryptor? _decryptor;
  final DiscordH264Depacketizer _depacketizer;

  /// Feeds one RTP payload in.
  ///
  /// Returns the plaintext access unit when [marker] closes a picture, or
  /// `null` while the picture is still arriving. A picture that will not
  /// decrypt is dropped whole rather than raised: a key that has not reached
  /// this client yet is ordinary at the start of a share, and the next picture
  /// usually decrypts. What it looks like from outside is packets arriving and
  /// no pictures coming out, which the viewer counts separately.
  Uint8List? accept(Uint8List payload, {required bool marker}) {
    final encrypted = _depacketizer.accept(payload, marker: marker);
    if (encrypted == null) return null;
    final decryptor = _decryptor;
    if (decryptor == null) return encrypted;
    try {
      return decryptor(encrypted);
    } on Object {
      return null;
    }
  }
}
