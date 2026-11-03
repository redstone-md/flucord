import 'package:flutter/material.dart';

import '../../domain/video_decoder.dart';

/// One participant's camera, drawn in their tile from the texture it is
/// decoded on (ADR-0009). The tile is rebuilt only when the texture changes;
/// each picture reaches the screen without passing through Dart.
class CameraPicture extends StatelessWidget {
  const CameraPicture({required this.texture, super.key});

  final VideoTexture texture;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('camera-picture'),
    color: Colors.black,
    child: FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: texture.width.toDouble(),
        height: texture.height.toDouble(),
        child: Texture(textureId: texture.id),
      ),
    ),
  );
}
