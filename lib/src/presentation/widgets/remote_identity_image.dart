import 'package:flutter/material.dart';

import 'data_uri_image.dart';
import 'motion_scope.dart';

/// An avatar, banner or icon from Discord's CDN over [fallback]. A staged
/// picture the user has not saved yet comes as a `data:` URI instead.
class RemoteIdentityImage extends StatelessWidget {
  const RemoteIdentityImage({
    required this.url,
    required this.fallback,
    this.imageKey,
    this.animatesOnHover = true,
    this.playsAnimations = true,
    super.key,
  });

  final String? url;
  final Widget fallback;
  final Key? imageKey;

  /// Whether an animated asset holds still until the pointer is on it, which
  /// is what Discord does with avatars, icons and status emoji. The pointer
  /// counts on the [MotionHoverRegion] around the image, such as its row or
  /// card, or on the image itself without one. Emoji that Discord plays all
  /// the time pass false. A still asset ignores this.
  final bool animatesOnHover;

  /// The account's answer to whether emoji may move at all. Off means the
  /// webp first frame is drawn instead, which is the same glyph.
  final bool playsAnimations;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    final stillUrl = imageUrl != null && animatesOnHover
        ? _stillFrameOf(imageUrl)
        : null;
    if (imageUrl != null && !playsAnimations) {
      return Stack(
        fit: StackFit.expand,
        children: [fallback, _image(_stillFrameOf(imageUrl) ?? imageUrl)],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        if (imageUrl != null)
          if (stillUrl == null)
            _image(imageUrl)
          else
            _HoverAnimatedImage(
              still: stillUrl,
              animated: imageUrl,
              builder: _image,
            ),
      ],
    );
  }

  Widget _image(String url) => Image(
    image: url.startsWith('data:') ? DataUriImage(url) : NetworkImage(url),
    key: imageKey,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  /// The still form of an animated asset, or null where there is none.
  ///
  /// Discord serves an `a_`-prefixed hash as both `.gif` and `.webp`, the
  /// second being its first frame, so the two addresses differ only in their
  /// extension. The size and quality arguments ride along in the query. An
  /// avatar decoration is an animated PNG that `passthrough=false` stills.
  static String? _stillFrameOf(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path;
    if (uri == null || path == null) return null;
    if (uri.queryParameters['passthrough'] == 'true') {
      return uri
          .replace(
            queryParameters: {...uri.queryParameters, 'passthrough': 'false'},
          )
          .toString();
    }
    if (!path.endsWith('.gif')) return null;
    return uri
        .replace(path: '${path.substring(0, path.length - 4)}.webp')
        .toString();
  }
}

/// Swaps a still asset for its animated form while the pointer is over it
/// and the motion rule allows it.
class _HoverAnimatedImage extends StatefulWidget {
  const _HoverAnimatedImage({
    required this.still,
    required this.animated,
    required this.builder,
  });

  final String still;
  final String animated;
  final Widget Function(String url) builder;

  @override
  State<_HoverAnimatedImage> createState() => _HoverAnimatedImageState();
}

class _HoverAnimatedImageState extends State<_HoverAnimatedImage> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final region = MotionHoverRegion.hoveredOf(context);
    final playing = (region ?? _hovered) && MotionScope.allows(context);
    final image = widget.builder(playing ? widget.animated : widget.still);
    if (region != null) return image;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: image,
    );
  }
}
