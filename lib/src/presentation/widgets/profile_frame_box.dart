import 'package:flutter/widgets.dart';

import '../../domain/profile_frame.dart';

/// Draws a profile [frame] around [child], the card, as Discord does: the
/// frame is scaled to the card's width and reaches past its edges, with
/// `front` pictures over the card and `back` ones behind it. With no frame
/// it is just [child].
///
/// Nothing around the card may clip it, or the overhang is cut off.
class ProfileFrameBox extends StatelessWidget {
  const ProfileFrameBox({required this.frame, required this.child, super.key});

  final ProfileFrameConfig? frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    if (frame == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (frame.layers.any((layer) => !layer.inFront))
          _layers(frame, inFront: false),
        child,
        if (frame.layers.any((layer) => layer.inFront))
          _layers(frame, inFront: true),
      ],
    );
  }

  static Widget _layers(ProfileFrameConfig frame, {required bool inFront}) =>
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: LayoutBuilder(
              key: ValueKey('profile-frame-${inFront ? 'front' : 'back'}'),
              builder: (context, card) {
                final scale = card.maxWidth / frame.innerWidth;
                final side = -frame.overflowHorizontal * scale;
                final top = -frame.overflowTop * scale;
                final bottom = -frame.overflowBottom * scale;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final layer in frame.layers)
                      if (layer.inFront == inFront)
                        switch (layer.anchor) {
                          ProfileFrameAnchor.top => Positioned(
                            left: side,
                            right: side,
                            top: top,
                            child: _picture(layer.src, BoxFit.fitWidth),
                          ),
                          ProfileFrameAnchor.bottom => Positioned(
                            left: side,
                            right: side,
                            bottom: bottom,
                            child: _picture(layer.src, BoxFit.fitWidth),
                          ),
                          ProfileFrameAnchor.center => Positioned(
                            left: side,
                            right: side,
                            top: top,
                            bottom: bottom,
                            child: _picture(layer.src, BoxFit.fill),
                          ),
                        },
                  ],
                );
              },
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
