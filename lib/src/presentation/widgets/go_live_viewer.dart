import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/video_decoder.dart';
import '../../theme/flucord_theme.dart';

/// Draws somebody else's Go Live stream.
///
/// Frames arrive as raw BGRA rather than an encoded image, so they go through
/// `decodeImageFromPixels` instead of `Image.memory`: there is no PNG header
/// here, and the pixels are already what a texture wants.
/// Turns a decoded frame into something the tree can draw.
///
/// Injected so the widget's own behaviour — dropping a frame that arrives
/// mid-conversion, replacing the picture, surviving a teardown — can be tested
/// without the engine's image pipeline and its own timing.
typedef PictureConverter =
    void Function(DecodedVideoFrame frame, ValueChanged<ui.Image> onDecoded);

/// The default converter: the engine's own BGRA decode.
///
/// Named rather than private because the participant tiles draw the same
/// pictures and would otherwise each need their own copy of it.
void decodePictureWithEngine(
  DecodedVideoFrame frame,
  ValueChanged<ui.Image> onDecoded,
) => ui.decodeImageFromPixels(
  frame.pixels,
  frame.width,
  frame.height,
  ui.PixelFormat.bgra8888,
  onDecoded,
);

class GoLiveViewer extends StatefulWidget {
  const GoLiveViewer({
    required this.frames,
    this.label = '',
    this.converter = decodePictureWithEngine,
    super.key,
  });

  final Stream<DecodedVideoFrame> frames;

  /// Whose stream this is, shown until the first picture arrives.
  final String label;

  final PictureConverter converter;

  @override
  State<GoLiveViewer> createState() => _GoLiveViewerState();
}

class _GoLiveViewerState extends State<GoLiveViewer> {
  StreamSubscription<DecodedVideoFrame>? _subscription;
  ui.Image? _image;
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant GoLiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frames, widget.frames)) _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = widget.frames.listen(_accept);
  }

  void _accept(DecodedVideoFrame frame) {
    // A frame whose buffer does not match its dimensions would be drawn as
    // garbage, and one arriving mid-conversion is simply dropped: showing the
    // newest picture matters more than showing every picture.
    if (!frame.isComplete || _converting) return;
    _converting = true;
    widget.converter(frame, (image) {
      _converting = false;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return ColoredBox(
        key: const ValueKey('go-live-waiting'),
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Waiting for ${widget.label}',
                  style: TextStyle(color: context.surfaces.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      key: const ValueKey('go-live-picture'),
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: image.width.toDouble(),
          height: image.height.toDouble(),
          child: RawImage(image: image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
