import 'package:flutter/material.dart';

import '../../theme/flucord_radius.dart';
import 'rail_tile.dart';
import 'remote_identity_image.dart';

/// A square of artwork, such as a game's or a server's, or [monogram] on
/// [color] where there is none. The Active now column and the activity card
/// both draw their art with it.
class ArtTile extends StatelessWidget {
  const ArtTile({
    required this.url,
    required this.monogram,
    required this.color,
    this.size = 40,
    this.imageKey,
    super.key,
  });

  /// The tile's corners. A card around a tile adds its padding to this, so
  /// the two curves stay concentric.
  static const radius = FlucordRadius.mediumCorner;

  final String? url;
  final String monogram;
  final Color color;
  final double size;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.all(radius),
    child: SizedBox.square(
      dimension: size,
      child: ColoredBox(
        color: color,
        child: RemoteIdentityImage(
          url: url,
          imageKey: imageKey,
          fallback: RailMonogram(monogram),
        ),
      ),
    ),
  );
}
