import 'package:flutter/material.dart';

/// A few round faces in a row, each over the one before by [overlap], with
/// a ring in [ringColor] to part them. The profile card's mutual friends and
/// the Active now column's voice channel both draw them.
class OverlappingFaces extends StatelessWidget {
  const OverlappingFaces({
    required this.faces,
    required this.size,
    required this.ringColor,
    this.overlap = 4,
    super.key,
  });

  static const _ring = 2.0;

  /// The faces, each drawn round at [size].
  final List<Widget> faces;
  final double size;
  final Color ringColor;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final outer = size + 2 * _ring;
    final step = outer - overlap - _ring;
    return SizedBox(
      width: faces.isEmpty ? 0 : outer + (faces.length - 1) * step,
      height: outer,
      child: Stack(
        children: [
          for (var index = 0; index < faces.length; index++)
            Positioned(
              left: index * step,
              child: Container(
                width: outer,
                height: outer,
                padding: const EdgeInsets.all(_ring),
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(child: faces[index]),
              ),
            ),
        ],
      ),
    );
  }
}
