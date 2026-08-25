import 'package:flutter/material.dart';

class RemoteIdentityImage extends StatelessWidget {
  const RemoteIdentityImage({
    required this.url,
    required this.fallback,
    this.imageKey,
    this.animatesOnHover = false,
    super.key,
  });

  final String? url;
  final Widget fallback;
  final Key? imageKey;

  /// Whether an animated asset holds still until the pointer is on it, which
  /// is what Discord does with an animated icon. A still asset ignores this.
  final bool animatesOnHover;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    final stillUrl = imageUrl != null && animatesOnHover
        ? _stillFrameOf(imageUrl)
        : null;
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

  Widget _image(String url) => Image.network(
    url,
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
  /// extension. The size and quality arguments ride along in the query.
  static String? _stillFrameOf(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path;
    if (uri == null || path == null || !path.endsWith('.gif')) return null;
    return uri
        .replace(path: '${path.substring(0, path.length - 4)}.webp')
        .toString();
  }
}

/// Swaps a still asset for its animated form while the pointer is over it.
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
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(_hovered ? widget.animated : widget.still),
  );
}
