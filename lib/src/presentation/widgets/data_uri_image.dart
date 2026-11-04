import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A picture held as a `data:` URI, as the profile picker stages an avatar
/// or a banner before it is saved.
///
/// Keyed by the URI rather than by its bytes, so the image cache decodes one
/// staged picture once, not on every rebuild of the form around it.
@immutable
final class DataUriImage extends ImageProvider<DataUriImage> {
  const DataUriImage(this.uri);

  final String uri;

  @override
  Future<DataUriImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DataUriImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async => decode(
    await ui.ImmutableBuffer.fromUint8List(
      UriData.parse(uri).contentAsBytes(),
    ),
  );

  @override
  bool operator ==(Object other) => other is DataUriImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
