import 'dart:typed_data';

/// Rewrites H.264 SPS units into the shape Discord's video path accepts.
///
/// Discord drops a stream whose SPS does not carry
/// `bitstream_restriction_flag = 1` and `max_num_reorder_frames = 0`: the
/// connection opens, the first picture may even reach a viewer, and then the
/// stream dies with error 2015 or an endless loading spinner. Windows'
/// Media Foundation encoder does not set the pair, so every SPS is rewritten
/// on its way to the wire rather than configured at the encoder, which is the
/// one approach that also works for hardware encoders and pre-encoded sources.
///
/// A unit that does not parse is passed through untouched: corrupting an SPS
/// is strictly worse than sending one without the flags.
abstract final class DiscordH264Sps {
  /// Rewrites every SPS in one Annex B access unit, leaving other NALs alone.
  ///
  /// Each NAL is re-emitted behind the start code it arrived behind, four-byte
  /// codes included, so a unit that is not rewritten comes out byte for byte.
  static Uint8List rewriteAccessUnit(Uint8List accessUnit) {
    final output = BytesBuilder(copy: false);
    var codeStart = -1;
    var nalStart = 0;
    for (var i = 0; i + 2 < accessUnit.length; i++) {
      if (accessUnit[i] != 0 || accessUnit[i + 1] != 0 || accessUnit[i + 2] != 1) {
        continue;
      }
      nalStart = i + 3;
      // A zero right before the code belongs to the code: a clean NAL always
      // ends in the RBSP stop bit, never in zero.
      codeStart = i > 0 && accessUnit[i - 1] == 0 ? i - 1 : i;
      break;
    }
    if (codeStart < 0) return accessUnit;
    output.add(accessUnit.sublist(0, codeStart));
    while (codeStart < accessUnit.length) {
      final nextCode = _nextStartCode(accessUnit, nalStart);
      final nalEnd = nextCode < 0 ? accessUnit.length : nextCode;
      output.add(accessUnit.sublist(codeStart, nalStart));
      output.add(_rewriteNal(accessUnit.sublist(nalStart, nalEnd)));
      if (nextCode < 0) break;
      nalStart = nextCode + 3;
      codeStart = nextCode > nalEnd && accessUnit[nextCode - 1] == 0
          ? nextCode - 1
          : nextCode;
    }
    return output.toBytes();
  }

  /// The offset of the next start code at or after [from], or -1.
  static int _nextStartCode(Uint8List bytes, int from) {
    for (var i = from; i + 2 < bytes.length; i++) {
      if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1) return i;
    }
    return -1;
  }

  static Uint8List _rewriteNal(Uint8List nal) {
    if (nal.isEmpty || (nal[0] & 0x1f) != 7) return nal;
    try {
      return _rewriteSps(nal);
    } on Object {
      return nal;
    }
  }

  static Uint8List _rewriteSps(Uint8List nal) {
    final reader = _RbspReader(_removeEmulationPrevention(nal.sublist(1)));
    final writer = _RbspWriter();

    final profileIdc = reader.u(8);
    writer.u(8, profileIdc);
    writer.u(8, reader.u(8)); // constraint flags and reserved bits
    writer.u(8, reader.u(8)); // level_idc
    writer.ue(reader.ue()); // seq_parameter_set_id

    var chromaFormatIdc = 1;
    if (_highProfiles.contains(profileIdc)) {
      chromaFormatIdc = reader.ue();
      writer.ue(chromaFormatIdc);
      if (chromaFormatIdc == 3) writer.u(1, reader.u(1));
      writer.ue(reader.ue()); // bit_depth_luma_minus8
      writer.ue(reader.ue()); // bit_depth_chroma_minus8
      writer.u(1, reader.u(1)); // qpprime_y_zero_transform_bypass_flag
      final scalingListPresent = reader.u(1);
      writer.u(1, scalingListPresent);
      if (scalingListPresent == 1) {
        final listCount = chromaFormatIdc == 3 ? 12 : 8;
        for (var i = 0; i < listCount; i++) {
          final present = reader.u(1);
          writer.u(1, present);
          if (present == 1) _copyScalingList(reader, writer, i < 6 ? 16 : 64);
        }
      }
    }

    writer.ue(reader.ue()); // log2_max_frame_num_minus4
    final picOrderCountType = reader.ue();
    writer.ue(picOrderCountType);
    if (picOrderCountType == 0) {
      writer.ue(reader.ue()); // log2_max_pic_order_cnt_lsb_minus4
    } else if (picOrderCountType == 1) {
      writer.u(1, reader.u(1)); // delta_pic_order_always_zero_flag
      writer.se(reader.se()); // offset_for_non_ref_pic
      writer.se(reader.se()); // offset_for_top_to_bottom_field
      final count = reader.ue();
      writer.ue(count);
      for (var i = 0; i < count; i++) {
        writer.se(reader.se()); // offset_for_ref_frame[i]
      }
    }

    final maxNumRefFrames = reader.ue();
    writer.ue(maxNumRefFrames);
    writer.u(1, reader.u(1)); // gaps_in_frame_num_value_allowed_flag
    writer.ue(reader.ue()); // pic_width_in_mbs_minus1
    writer.ue(reader.ue()); // pic_height_in_map_units_minus1
    final frameMbsOnlyFlag = reader.u(1);
    writer.u(1, frameMbsOnlyFlag);
    if (frameMbsOnlyFlag == 0) writer.u(1, reader.u(1));
    writer.u(1, reader.u(1)); // direct_8x8_inference_flag
    final frameCroppingFlag = reader.u(1);
    writer.u(1, frameCroppingFlag);
    if (frameCroppingFlag == 1) {
      writer.ue(reader.ue());
      writer.ue(reader.ue());
      writer.ue(reader.ue());
      writer.ue(reader.ue());
    }

    // Whether a VUI follows. Past the picture geometry only the trailing bits
    // may remain, which reads as no VUI at all.
    final vuiPresent = reader.remaining > 0 ? reader.u(1) : 0;
    writer.u(1, 1);

    if (vuiPresent == 0) {
      // A VUI written from scratch: nothing but the restriction block.
      writer.u(2, 0); // aspect ratio and overscan absent
      writer.u(1, 0); // video signal type absent
      writer.u(5, 0); // chroma location through picture structure absent
      writer.u(1, 1); // bitstream_restriction_flag
      _writeRestriction(writer, maxNumRefFrames);
    } else {
      _copyVuiUpToRestriction(reader, writer);
      final restrictionPresent = reader.u(1);
      writer.u(1, 1);
      if (restrictionPresent == 0) {
        _writeRestriction(writer, maxNumRefFrames);
      } else {
        writer.u(1, reader.u(1)); // motion_vectors_over_pic_boundaries_flag
        writer.ue(reader.ue()); // max_bytes_per_pic_denom
        writer.ue(reader.ue()); // max_bits_per_mb_denom
        writer.ue(reader.ue()); // log2_max_mv_length_horizontal
        writer.ue(reader.ue()); // log2_max_mv_length_vertical
        reader.ue(); // max_num_reorder_frames, replaced below
        writer.ue(0);
        reader.ue(); // max_dec_frame_buffering, replaced below
        writer.ue(maxNumRefFrames);
      }
    }

    final rbsp = writer.toBytes();
    final out = BytesBuilder(copy: false)..add([nal[0]]);
    return (out..add(_addEmulationPrevention(rbsp))).toBytes();
  }

  static void _copyVuiUpToRestriction(_RbspReader r, _RbspWriter w) {
    final aspectRatioPresent = r.u(1);
    w.u(1, aspectRatioPresent);
    if (aspectRatioPresent == 1) {
      final aspectRatio = r.u(8);
      w.u(8, aspectRatio);
      if (aspectRatio == 255) {
        w.u(16, r.u(16));
        w.u(16, r.u(16));
      }
    }

    final overscanPresent = r.u(1);
    w.u(1, overscanPresent);
    if (overscanPresent == 1) w.u(1, r.u(1));

    // Read but dropped: Discord's decoder takes the stream without a video
    // signal type, and writing one back is where compat bugs lived.
    final videoSignalTypePresent = r.u(1);
    w.u(1, 0);
    if (videoSignalTypePresent == 1) {
      r.u(3); // video_format
      r.u(1); // video_full_range_flag
      final colourDescriptionPresent = r.u(1);
      if (colourDescriptionPresent == 1) {
        r.u(8); // colour_primaries
        r.u(8); // transfer_characteristics
        r.u(8); // matrix_coefficients
      }
    }

    final chromaLocPresent = r.u(1);
    w.u(1, chromaLocPresent);
    if (chromaLocPresent == 1) {
      w.ue(r.ue()); // chroma_sample_loc_type_top_field
      w.ue(r.ue()); // chroma_sample_loc_type_bottom_field
    }

    final timingPresent = r.u(1);
    w.u(1, timingPresent);
    if (timingPresent == 1) {
      w.u(32, r.u(32)); // num_units_in_tick
      w.u(32, r.u(32)); // time_scale
      w.u(1, r.u(1)); // fixed_frame_rate_flag
    }

    final nalHrdPresent = r.u(1);
    w.u(1, nalHrdPresent);
    if (nalHrdPresent == 1) _copyHrd(r, w);

    final vclHrdPresent = r.u(1);
    w.u(1, vclHrdPresent);
    if (vclHrdPresent == 1) _copyHrd(r, w);

    if (nalHrdPresent == 1 || vclHrdPresent == 1) {
      w.u(1, r.u(1)); // low_delay_hrd_flag
    }

    w.u(1, r.u(1)); // pic_struct_present_flag
  }

  static void _writeRestriction(_RbspWriter w, int maxNumRefFrames) {
    w.u(1, 1); // motion_vectors_over_pic_boundaries_flag
    w.ue(2); // max_bytes_per_pic_denom
    w.ue(1); // max_bits_per_mb_denom
    w.ue(16); // log2_max_mv_length_horizontal
    w.ue(16); // log2_max_mv_length_vertical
    // What the whole rewrite exists for: no reorder buffer, so every frame is
    // shown the moment it is decoded.
    w.ue(0); // max_num_reorder_frames
    w.ue(maxNumRefFrames); // max_dec_frame_buffering
  }

  static void _copyHrd(_RbspReader r, _RbspWriter w) {
    final cpbCount = r.ue();
    w.ue(cpbCount);
    w.u(4, r.u(4)); // bit_rate_scale
    w.u(4, r.u(4)); // cpb_size_scale
    for (var i = 0; i <= cpbCount; i++) {
      w.ue(r.ue()); // bit_rate_value
      w.ue(r.ue()); // cpb_size_value
      w.u(1, r.u(1)); // cbr_flag
    }
    w.u(5, r.u(5)); // initial_cpb_removal_delay_length_minus1
    w.u(5, r.u(5)); // cpb_removal_delay_length_minus1
    w.u(5, r.u(5)); // dpb_output_delay_length_minus1
    w.u(5, r.u(5)); // time_offset_length
  }

  static void _copyScalingList(_RbspReader r, _RbspWriter w, int size) {
    var lastScale = 8;
    var nextScale = 8;
    for (var i = 0; i < size; i++) {
      var deltaScale = 0;
      if (nextScale != 0) {
        deltaScale = r.se();
        w.se(deltaScale);
        nextScale = (lastScale + deltaScale + 256) % 256;
      }
      lastScale = nextScale != 0 ? nextScale : lastScale;
    }
  }

  static Uint8List _removeEmulationPrevention(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < data.length) {
      if (i + 2 < data.length &&
          data[i] == 0 &&
          data[i + 1] == 0 &&
          data[i + 2] == 3) {
        out.addByte(0);
        out.addByte(0);
        i += 3;
      } else {
        out.addByte(data[i]);
        i++;
      }
    }
    return out.toBytes();
  }

  static Uint8List _addEmulationPrevention(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var zeros = 0;
    for (final byte in data) {
      if (zeros >= 2 && byte <= 3) {
        out.addByte(3);
        zeros = 0;
      }
      out.addByte(byte);
      zeros = byte == 0 ? zeros + 1 : 0;
    }
    return out.toBytes();
  }

  /// Profile ids whose SPS carries the chroma, bit depth and scaling list
  /// syntax the baseline and main profiles leave out.
  static const _highProfiles = {
    100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 144,
  };
}

final class _RbspReader {
  _RbspReader(this._data);

  final Uint8List _data;
  int _position = 0;

  int get remaining => _data.length * 8 - _position;

  int u(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      final byteIndex = _position >> 3;
      if (byteIndex >= _data.length) {
        throw const FormatException('H.264 SPS ended mid-field');
      }
      value = (value << 1) | ((_data[byteIndex] >> (7 - (_position & 7))) & 1);
      _position++;
    }
    return value;
  }

  int ue() {
    var zeros = 0;
    while (u(1) == 0) {
      zeros++;
      if (zeros > 31) {
        throw const FormatException('H.264 Exp-Golomb code runs too long');
      }
    }
    return zeros == 0 ? 0 : (1 << zeros) - 1 + u(zeros);
  }

  int se() {
    final code = ue();
    if (code == 0) return 0;
    return code.isOdd ? (code + 1) >> 1 : -(code >> 1);
  }
}

final class _RbspWriter {
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

  void se(int value) => ue(value > 0 ? 2 * value - 1 : -2 * value);

  /// The bits written, closed with the RBSP stop bit and padded to a byte.
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
