import 'dart:typed_data';

// TEMP DIAGNOSTICS (remove after the live picture check).
import '../../app_log.dart';

/// Rebuilds Annex B access units from RTP payloads.
///
/// The receiving half of RFC 6184, and the only way this client can check its
/// own sender without a second account watching: what comes out of here has to
/// be byte-identical to what the encoder produced, and a decoder has to accept
/// it. A packetiser that quietly corrupts a fragment header produces packets
/// that look reasonable and a picture nobody can draw.
final class DiscordH264Depacketizer {
  final List<int> _fragment = [];
  final List<int> _accessUnit = [];

  int _fragmentHeader = 0;
  bool _dropping = false;

  // TEMP DIAGNOSTICS (remove after the live picture check).
  int _tracedNals = 0;
  bool _tracingNal = false;
  final List<String> _trace = [];
  int _stapLogged = 0;
  int _orphanContinuations = 0;
  int _cutNals = 0;

  /// Feeds one RTP payload in.
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
      // TEMP DIAGNOSTICS (remove after the live picture check).
      if (_stapLogged < 2) {
        _stapLogged++;
        AppLog.warning(
          'stream',
          'picture diagnostic: STAP-A payload len ${payload.length}',
        );
      }
      _acceptAggregate(payload);
    } else {
      _appendNal(payload);
    }
    if (!marker) return null;
    final unit = Uint8List.fromList(_accessUnit);
    _accessUnit.clear();
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
      // TEMP DIAGNOSTICS (remove after the live picture check): a new NAL
      // starting while one is still open means its final fragment was lost
      // or arrived out of order.
      if (_fragment.isNotEmpty && ++_cutNals <= 3) {
        AppLog.warning(
          'stream',
          'picture diagnostic: fragment anomaly: a new NAL started while '
          'the previous held ${_fragment.length} bytes',
        );
      }
      _fragment
        ..clear()
        // The original NAL header is the indicator's importance bits and the
        // fragment header's type, put back together.
        ..add((indicator & 0xe0) | (header & 0x1f));
      _fragmentHeader = _fragment.first;
      _dropping = false;
      _tracingNal = _tracedNals < 2;
      if (_tracingNal) {
        _trace
          ..clear()
          ..add('start(type ${header & 0x1f}, ${payload.length}B)');
      }
    } else if (_fragment.isEmpty) {
      // A continuation with no start means the first packet was lost. The
      // whole NAL is unusable, so the rest of it is dropped rather than
      // producing a slice that begins in the middle.
      if (++_orphanContinuations <= 3) {
        AppLog.warning(
          'stream',
          'picture diagnostic: fragment anomaly: continuation without a '
          'start fragment',
        );
      }
      _dropping = true;
      return;
    }
    if (_dropping) return;
    if (_tracingNal && !isFirst) {
      _trace.add('${isFinal ? 'end' : 'mid'}(${payload.length}B)');
    }
    _fragment.addAll(payload.sublist(2));
    if (isFinal) {
      if (_tracingNal) {
        _tracedNals++;
        AppLog.warning(
          'stream',
          'picture diagnostic: NAL trace: ${_trace.join(' ')}',
        );
        _tracingNal = false;
      }
      _appendNal(Uint8List.fromList(_fragment));
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

  /// Parameter sets take the four-byte start code and everything else the
  /// three-byte one, which is what the encoder emits and what a decoder is
  /// least surprised by.
  void _appendNal(Uint8List nal) {
    if (nal.isEmpty) return;
    final type = nal[0] & 0x1f;
    if (type == 7 || type == 8 || _accessUnit.isEmpty) {
      _accessUnit.addAll(const [0, 0, 0, 1]);
    } else {
      _accessUnit.addAll(const [0, 0, 1]);
    }
    _accessUnit.addAll(nal);
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
