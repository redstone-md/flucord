import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_h264_sps.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes bit strings the way an encoder would, so the tests can name the
/// SPS fields instead of quoting hex.
final class _Bits {
  final List<int> _bits = [];

  void u(int count, int value) {
    for (var i = count - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1);
    }
  }

  void ue(int value) {
    final code = value + 1;
    final length = code.bitLength;
    for (var i = 0; i < length - 1; i++) {
      _bits.add(0);
    }
    for (var i = length - 1; i >= 0; i--) {
      _bits.add((code >> i) & 1);
    }
  }

  Uint8List toBytes() {
    final bits = [..._bits, 1];
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    final out = Uint8List(bits.length ~/ 8);
    for (var i = 0; i < out.length; i++) {
      var byte = 0;
      for (var j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i * 8 + j];
      }
      out[i] = byte;
    }
    return out;
  }
}

/// Reads the SPS fields the tests assert on, baseline profile only, with the
/// structural choices the inputs below always make: frame_mbs_only, no crop,
/// pic_order_cnt_type 0. Parsed eagerly, in bit order.
final class _Sps {
  _Sps(Uint8List nal)
    : assert((nal[0] & 0x1f) == 7, 'not an SPS'),
      _data = nal.sublist(1) {
    profileIdc = _u(8);
    _u(8); // constraint flags
    levelIdc = _u(8);
    spsId = _ue();
    _ue(); // log2_max_frame_num_minus4
    _ue(); // pic_order_cnt_type
    _ue(); // log2_max_pic_order_cnt_lsb_minus4
    maxNumRefFrames = _ue();
    _u(1); // gaps_in_frame_num_value_allowed_flag
    widthInMbs = _ue();
    heightInMapUnits = _ue();
    _u(1); // frame_mbs_only_flag
    _u(1); // direct_8x8_inference_flag
    _u(1); // frame_cropping_flag
    vuiPresent = _u(1);
    aspectRatioPresent = _u(1);
    videoSignalTypePresent = _u(2) & 1; // after overscan_info_present
    _u(1); // chroma_loc_info_present_flag
    _u(1); // timing_info_present_flag
    _u(1); // nal_hrd_parameters_present_flag
    _u(1); // vcl_hrd_parameters_present_flag
    _u(1); // pic_struct_present_flag
    bitstreamRestrictionFlag = _u(1);
    _u(1); // motion_vectors_over_pic_boundaries_flag
    _ue(); // max_bytes_per_pic_denom
    _ue(); // max_bits_per_mb_denom
    _ue(); // log2_max_mv_length_horizontal
    _ue(); // log2_max_mv_length_vertical
    maxNumReorderFrames = _ue();
    maxDecFrameBuffering = _ue();
  }

  final Uint8List _data;
  int _position = 0;

  late final int profileIdc;
  late final int levelIdc;
  late final int spsId;
  late final int maxNumRefFrames;
  late final int widthInMbs;
  late final int heightInMapUnits;
  late final int vuiPresent;
  late final int aspectRatioPresent;
  late final int videoSignalTypePresent;
  late final int bitstreamRestrictionFlag;
  late final int maxNumReorderFrames;
  late final int maxDecFrameBuffering;

  int _u(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value =
          (value << 1) |
          ((_data[_position >> 3] >> (7 - (_position & 7))) & 1);
      _position++;
    }
    return value;
  }

  int _ue() {
    var zeros = 0;
    while (_u(1) == 0) {
      zeros++;
    }
    return zeros == 0 ? 0 : (1 << zeros) - 1 + _u(zeros);
  }
}

/// A baseline SPS with the structural simplifications the reader above knows:
/// no crop, frame_mbs_only, picture order type 0.
Uint8List _sps({required bool vuiPresent, int vuiReorderFrames = 2}) {
  final bits = _Bits()
    ..u(8, 66) // profile_idc: baseline
    ..u(8, 0) // constraint flags
    ..u(8, 30) // level_idc
    ..ue(0) // seq_parameter_set_id
    ..ue(0) // log2_max_frame_num_minus4
    ..ue(0) // pic_order_cnt_type
    ..ue(0) // log2_max_pic_order_cnt_lsb_minus4
    ..ue(2) // max_num_ref_frames
    ..u(1, 0) // gaps_in_frame_num_value_allowed_flag
    ..ue(20) // pic_width_in_mbs_minus1
    ..ue(11) // pic_height_in_map_units_minus1
    ..u(1, 1) // frame_mbs_only_flag
    ..u(1, 1) // direct_8x8_inference_flag
    ..u(1, 0) // frame_cropping_flag
    ..u(1, vuiPresent ? 1 : 0);
  if (vuiPresent) {
    bits
      ..u(1, 0) // aspect_ratio_info_present_flag
      ..u(1, 0) // overscan_info_present_flag
      ..u(1, 0) // video_signal_type_present_flag
      ..u(1, 0) // chroma_loc_info_present_flag
      ..u(1, 0) // timing_info_present_flag
      ..u(1, 0) // nal_hrd_parameters_present_flag
      ..u(1, 0) // vcl_hrd_parameters_present_flag
      ..u(1, 0) // pic_struct_present_flag
      ..u(1, 1) // bitstream_restriction_flag
      ..u(1, 1) // motion_vectors_over_pic_boundaries_flag
      ..ue(2) // max_bytes_per_pic_denom
      ..ue(1) // max_bits_per_mb_denom
      ..ue(16) // log2_max_mv_length_horizontal
      ..ue(16) // log2_max_mv_length_vertical
      ..ue(vuiReorderFrames) // max_num_reorder_frames
      ..ue(5); // max_dec_frame_buffering
  }
  return Uint8List.fromList([0x67, ...bits.toBytes()]);
}

Uint8List _annexB(List<Uint8List> nals) => Uint8List.fromList([
  for (final nal in nals) ...[0, 0, 0, 1, ...nal],
]);

void main() {
  test('an SPS without a VUI gains one with the required flags', () {
    final rewritten = DiscordH264Sps.rewriteAccessUnit(
      _annexB([_sps(vuiPresent: false)]),
    );

    // A whole NAL with a start code came back.
    expect(rewritten.length, greaterThan(4 + 4));
    final sps = _Sps(rewritten.sublist(4));
    expect(sps.profileIdc, 66);
    expect(sps.levelIdc, 30);
    expect(sps.widthInMbs, 20);
    expect(sps.heightInMapUnits, 11);
    expect(sps.vuiPresent, 1);
    expect(sps.bitstreamRestrictionFlag, 1);
    expect(sps.maxNumReorderFrames, 0);
    expect(sps.maxDecFrameBuffering, 2);
  });

  test('an SPS with a reorder buffer loses it', () {
    final rewritten = DiscordH264Sps.rewriteAccessUnit(
      _annexB([_sps(vuiPresent: true, vuiReorderFrames: 2)]),
    );

    final sps = _Sps(rewritten.sublist(4));
    expect(sps.bitstreamRestrictionFlag, 1);
    expect(sps.maxNumReorderFrames, 0);
    expect(sps.maxDecFrameBuffering, 2);
  });

  test('other NALs in the access unit pass through untouched', () {
    final idr = Uint8List.fromList([0x65, 1, 2, 3]);
    final accessUnit = _annexB([_sps(vuiPresent: false), idr]);

    final rewritten = DiscordH264Sps.rewriteAccessUnit(accessUnit);

    // The IDR slice is byte for byte what went in, behind its start code.
    expect(rewritten.sublist(rewritten.length - idr.length), idr);
    // And the SPS in front of it changed.
    expect(rewritten.length, greaterThan(accessUnit.length));
  });

  test('a unit that does not parse comes back unchanged', () {
    final truncated = Uint8List.fromList([0, 0, 0, 1, 0x67, 0x42]);

    expect(DiscordH264Sps.rewriteAccessUnit(truncated), truncated);
  });

  test('a unit with no start code comes back unchanged', () {
    final bytes = Uint8List.fromList([0x67, 0x42, 1, 2, 3]);

    expect(DiscordH264Sps.rewriteAccessUnit(bytes), bytes);
  });
}
