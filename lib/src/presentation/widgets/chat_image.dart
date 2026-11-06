import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../../data/chat_image_cache.dart';

/// The picture at the address [addressAt] gives, kept in the disk cache and
/// decoded no larger than [size].
///
/// [addressAt] gets the size in device pixels, so an address on a media proxy
/// can ask for that size. An address that cannot ask keeps its full download
/// and is still decoded down, which keeps a large picture out of the image
/// cache at full size.
ImageProvider chatImage(
  BuildContext context, {
  required Size size,
  required String Function(int width, int height) addressAt,
}) {
  final scale = MediaQuery.devicePixelRatioOf(context);
  final width = (size.width * scale).round();
  final height = (size.height * scale).round();
  return ResizeImage(
    CachedNetworkImageProvider(
      addressAt(width, height),
      cacheManager: ChatImageCache.instance,
    ),
    width: width,
    height: height,
    policy: ResizeImagePolicy.fit,
  );
}

/// The largest box of this [ratio] that fits in [bounds].
///
/// A portrait picture fills the height and stops short of the width, so asking
/// for the full width would fetch pixels that are never drawn.
Size boxFitting(Size bounds, double ratio) {
  final width = math.min(bounds.width, bounds.height * ratio);
  return Size(width, width / ratio);
}

/// The smallest box of this [ratio] that covers [bounds].
///
/// A picture cropped to fill a tile has to be at least the tile in both
/// directions, or the part that shows is drawn upscaled.
Size boxCovering(Size bounds, double ratio) {
  final width = math.max(bounds.width, bounds.height * ratio);
  return Size(width, width / ratio);
}

/// A media proxy [address] that asks for this size, and for a still frame when
/// [stillFrame] is true.
///
/// Discord's media proxy resizes on request, so a photo taken on a phone costs
/// its thumbnail rather than its original.
String proxyAddressAtSize(
  Uri address, {
  required int width,
  required int height,
  bool stillFrame = false,
}) => address
    .replace(
      queryParameters: {
        ...address.queryParameters,
        'width': '$width',
        'height': '$height',
        if (stillFrame) 'format': 'png',
      },
    )
    .toString();

/// The first frame of a cdn GIF, which the cdn serves as the webp form.
String cdnStillFrameOf(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.path.endsWith('.gif')) return url;
  return parsed
      .replace(
        path: parsed.path.replaceRange(parsed.path.length - 4, null, '.webp'),
      )
      .toString();
}
