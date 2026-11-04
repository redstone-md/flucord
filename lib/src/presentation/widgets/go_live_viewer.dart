import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/video_decoder.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// Draws a Go Live stream: somebody else's, or the sender's own preview.
///
/// The stream is decoded onto a texture (ADR-0009). The pictures never pass
/// through Dart; only the texture's id and size do.
class GoLiveViewer extends StatefulWidget {
  const GoLiveViewer({
    required this.textures,
    this.label = '',
    this.showProgress = true,
    this.error,
    super.key,
  });

  /// The texture, each time it changes, or null while there is no picture
  /// to draw.
  final Stream<VideoTexture?> textures;

  /// Whose stream this is, shown until the first picture arrives.
  final String label;

  /// A compact tile can use a static waiting state so a room settling does not
  /// leave an animation running forever while Discord has not answered yet.
  final bool showProgress;

  /// Why there is no picture, if the session knows one. Shown instead of
  /// whatever is on the tile: a decoder that failed to open is a message,
  /// not a spinner turning forever, and a picture frozen by a suspend the
  /// decoder never came back from reads as a live stream that stalled.
  final Object? error;

  @override
  State<GoLiveViewer> createState() => _GoLiveViewerState();
}

class _GoLiveViewerState extends State<GoLiveViewer> {
  StreamSubscription<VideoTexture?>? _subscription;
  VideoTexture? _texture;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant GoLiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.textures, widget.textures)) _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _texture = null;
    _subscription = widget.textures.listen(
      (texture) => setState(() => _texture = texture),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    if (error != null) {
      return _stage('go-live-error', [
        FlucordIcon(
          FlucordIcons.error,
          size: 24,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 10),
        Text(
          'Stream unavailable',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: FlucordType.caption,
          ),
        ),
      ]);
    }
    final texture = _texture;
    if (texture == null) {
      return _waiting(context, widget.label, showProgress: widget.showProgress);
    }
    return ColoredBox(
      key: const ValueKey('go-live-picture'),
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: texture.width.toDouble(),
          height: texture.height.toDouble(),
          child: Texture(textureId: texture.id),
        ),
      ),
    );
  }
}

/// What a tile shows before its first picture.
Widget _waiting(
  BuildContext context,
  String label, {
  required bool showProgress,
}) => _stage('go-live-waiting', [
  if (showProgress)
    const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    )
  else
    const FlucordIcon(FlucordIcons.streaming, size: 24),
  if (label.isNotEmpty) ...[
    const SizedBox(height: 10),
    Text(
      'Waiting for $label',
      style: TextStyle(
        color: context.surfaces.muted,
        fontSize: FlucordType.caption,
      ),
    ),
  ],
]);

/// The full-height state a tile shows before its pictures: a black ground
/// with one message in the middle.
Widget _stage(String key, List<Widget> children) => ColoredBox(
  key: ValueKey(key),
  color: Colors.black,
  child: Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  ),
);
