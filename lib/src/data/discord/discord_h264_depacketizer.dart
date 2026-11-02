import 'dart:typed_data';

/// Rebuilds Annex B access units from RTP payloads.
///
/// The receiving half of RFC 6184, and the only way this client can check its
/// own sender without a second account watching: what comes out of here has to
/// be byte-identical to what the encoder produced, and a decoder has to accept
/// it. A packetiser that quietly corrupts a fragment header produces packets
/// that look reasonable and a picture nobody can draw.
///
/// The parts of a picture are held as views of the payloads they came from, and
/// are copied once, into the access unit, when the picture closes.
final class DiscordH264Depacketizer {
  static final Uint8List _startCode = Uint8List.fromList(const [0, 0, 0, 1]);

  /// The fragments of a NAL that has not finished, behind [_fragmentHeader].
  /// Kept apart from [_accessUnit], because a NAL that never finishes is lost.
  final List<Uint8List> _fragment = [];
  final BytesBuilder _accessUnit = BytesBuilder(copy: false);

  int _fragmentHeader = 0;
  bool _dropping = false;

  /// Feeds one RTP payload in. Its bytes are read until the picture closes, so
  /// nobody may change them before then.
  ///
  /// Returns the completed access unit when [marker] closes one, or `null`
  /// while the picture is still arriving.
  Uint8List? accept(Uint8List payload, {required bool marker}) {
    if (payload.isEmpty) return null;
    final type = payload[0] & 0x1f;
    if (type == 28) {
      _acceptFragment(payload);
    } else if (type == 24) {
      // STAP-A: several whole NALs behind one payload header, each preceded by
      // its 16-bit length. Not produced here, but a sender on the other side
      // may use it and a viewer that ignored it would lose parameter sets.
      _acceptAggregate(payload);
    } else {
      _appendNal(payload);
    }
    if (!marker) return null;
    final unit = _accessUnit.takeBytes();
    _fragment.clear();
    _dropping = false;
    return unit.isEmpty ? null : unit;
  }

  void _acceptFragment(Uint8List payload) {
    if (payload.length < 3) return;
    final indicator = payload[0];
    final header = payload[1];
    final isFirst = header & 0x80 != 0;
    final isFinal = header & 0x40 != 0;
    if (isFirst) {
      _fragment.clear();
      // The original NAL header is the indicator's importance bits and the
      // fragment header's type, put back together.
      _fragmentHeader = (indicator & 0xe0) | (header & 0x1f);
      _dropping = false;
    } else if (_fragment.isEmpty) {
      // A continuation with no start means the first packet was lost. The
      // whole NAL is unusable, so the rest of it is dropped rather than
      // producing a slice that begins in the middle.
      _dropping = true;
      return;
    }
    if (_dropping) return;
    _fragment.add(Uint8List.sublistView(payload, 2));
    if (isFinal) {
      _accessUnit
        ..add(_startCode)
        ..addByte(_fragmentHeader);
      _fragment.forEach(_accessUnit.add);
      _fragment.clear();
      _fragmentHeader = 0;
    }
  }

  void _acceptAggregate(Uint8List payload) {
    var offset = 1;
    while (offset + 2 <= payload.length) {
      final length = (payload[offset] << 8) | payload[offset + 1];
      offset += 2;
      if (length == 0 || offset + length > payload.length) return;
      _appendNal(Uint8List.sublistView(payload, offset, offset + length));
      offset += length;
    }
  }

  /// Every NAL gets the four-byte start code. That is the shape the official
  /// sender encrypts before it packetises (ADR-0005), and the group cipher
  /// authenticates those exact bytes: a picture reassembled with three-byte
  /// codes anywhere differs from the ciphertext and will not decrypt.
  void _appendNal(Uint8List nal) {
    if (nal.isEmpty) return;
    _accessUnit
      ..add(_startCode)
      ..add(nal);
  }

  /// The NAL header byte of the fragment being reassembled, or 0.
  int get pendingFragmentHeader => _fragmentHeader;

  /// Whether a picture is partly assembled.
  bool get hasPendingUnit => _accessUnit.isNotEmpty || _fragment.isNotEmpty;

  void reset() {
    _fragment.clear();
    _accessUnit.clear();
    _fragmentHeader = 0;
    _dropping = false;
  }
}
