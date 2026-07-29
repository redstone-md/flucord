import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/video_decoder.dart';
import 'go_live_viewer.dart';

/// One participant's camera, drawn in their tile.
///
/// Takes a frame rather than a stream: a room is a grid of tiles that rebuild
/// together, and a stream per tile would mean a subscription per participant
/// for pictures the controller already holds.
///
/// The conversion is asynchronous, so the previous picture stays on screen
/// until the next one is ready — a tile that blanked between frames would
/// flicker at the frame rate.
class CameraPicture extends StatefulWidget {
  const CameraPicture({
    required this.frame,
    this.converter = decodePictureWithEngine,
    super.key,
  });

  final DecodedVideoFrame frame;
  final PictureConverter converter;

  @override
  State<CameraPicture> createState() => _CameraPictureState();
}

class _CameraPictureState extends State<CameraPicture> {
  ui.Image? _image;
  DecodedVideoFrame? _converting;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void didUpdateWidget(covariant CameraPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) _convert();
  }

  void _convert() {
    final frame = widget.frame;
    // A frame that does not hold what its dimensions claim would be read past
    // its end by the engine.
    if (!frame.isComplete || identical(_converting, frame)) return;
    _converting = frame;
    widget.converter(frame, (image) {
      if (!mounted || !identical(_converting, frame)) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _converting = null;
      });
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return ColoredBox(
      key: const ValueKey('camera-picture'),
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: image.width.toDouble(),
          height: image.height.toDouble(),
          child: RawImage(image: image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
