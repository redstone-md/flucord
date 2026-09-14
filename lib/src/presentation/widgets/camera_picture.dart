import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/video_decoder.dart';
import 'go_live_viewer.dart';

/// One participant's camera, drawn in their tile.
///
/// Takes the picture the camera has now and the stream its future pictures
/// arrive on: the stream is the road the pictures travel once the tile
/// exists, so a camera runs at its own frame rate without rebuilding the
/// room around it.
///
/// The conversion is asynchronous, so the previous picture stays on screen
/// until the next one is ready — a tile that blanked between frames would
/// flicker at the frame rate.
class CameraPicture extends StatefulWidget {
  const CameraPicture({
    required this.frame,
    this.frames,
    this.converter = decodePictureWithEngine,
    super.key,
  });

  final DecodedVideoFrame frame;

  /// Where this camera's next pictures arrive. Null when the caller has only
  /// the one, which is all a test or a still tile needs.
  final Stream<DecodedVideoFrame>? frames;

  final PictureConverter converter;

  @override
  State<CameraPicture> createState() => _CameraPictureState();
}

class _CameraPictureState extends State<CameraPicture> {
  StreamSubscription<DecodedVideoFrame>? _framesSubscription;
  ui.Image? _image;
  DecodedVideoFrame? _converting;

  @override
  void initState() {
    super.initState();
    _listen();
    _show(widget.frame);
  }

  @override
  void didUpdateWidget(covariant CameraPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frames, widget.frames)) _listen();
    if (!identical(oldWidget.frame, widget.frame)) _show(widget.frame);
  }

  void _listen() {
    unawaited(_framesSubscription?.cancel());
    _framesSubscription = widget.frames?.listen(_show);
  }

  void _show(DecodedVideoFrame frame) {
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
    unawaited(_framesSubscription?.cancel());
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
