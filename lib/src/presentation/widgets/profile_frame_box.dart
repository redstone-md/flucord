import 'package:flutter/widgets.dart';

import '../../domain/profile_frame.dart';

/// Draws a profile [frame] around [child], a card [cardWidth] wide, as
/// Discord does: the frame is scaled to the card's width and reaches past
/// its edges, with `front` pictures over the card and `back` ones behind
/// it. With no frame it is just [child].
///
/// The box includes the overhang, so a popup that keeps the box on screen
/// keeps the whole frame on screen.
class ProfileFrameBox extends StatelessWidget {
  const ProfileFrameBox({
    required this.frame,
    required this.cardWidth,
    required this.child,
    super.key,
  });

  final ProfileFrameConfig? frame;
  final double cardWidth;
  final Widget child;

  /// How far [frame] reaches past a card [cardWidth] wide on each side.
  static EdgeInsets overhang(ProfileFrameConfig? frame, double cardWidth) {
    if (frame == null) return EdgeInsets.zero;
    final scale = cardWidth / frame.innerWidth;
    return EdgeInsets.fromLTRB(
      frame.overflowHorizontal * scale,
      frame.overflowTop * scale,
      frame.overflowHorizontal * scale,
      frame.overflowBottom * scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    if (frame == null) return child;
    return Stack(
      children: [
        if (frame.layers.any((layer) => !layer.inFront))
          _layers(frame, inFront: false),
        Padding(padding: overhang(frame, cardWidth), child: child),
        if (frame.layers.any((layer) => layer.inFront))
          _layers(frame, inFront: true),
      ],
    );
  }

  static Widget _layers(ProfileFrameConfig frame, {required bool inFront}) =>
      Positioned.fill(
        key: ValueKey('profile-frame-${inFront ? 'front' : 'back'}'),
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              children: [
                for (final layer in frame.layers)
                  if (layer.inFront == inFront)
                    switch (layer.anchor) {
                      ProfileFrameAnchor.top => Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: _picture(layer.src, BoxFit.fitWidth),
                      ),
                      ProfileFrameAnchor.bottom => Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _picture(layer.src, BoxFit.fitWidth),
                      ),
                      ProfileFrameAnchor.center => Positioned.fill(
                        child: _picture(layer.src, BoxFit.fill),
                      ),
                    },
              ],
            ),
          ),
        ),
      );

  static Widget _picture(String url, BoxFit fit) => Image.network(
    url,
    fit: fit,
    filterQuality: FilterQuality.medium,
    // A picture that fails to load is left out; the card stays as it is.
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
