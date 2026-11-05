import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Builds [child] once every one of [pictures] has loaded or failed to, and
/// nothing before.
///
/// Pictures that make up one look, such as the corners of a profile frame or
/// the intro and loop of a profile effect, then appear together and play
/// from their start, instead of one by one as each arrives. A picture that
/// fails does not hold the rest back. Other pictures wait again, so a look
/// that changes also appears whole.
class PicturesReady extends StatefulWidget {
  const PicturesReady({required this.pictures, required this.child, super.key});

  final List<ImageProvider> pictures;
  final Widget child;

  @override
  State<PicturesReady> createState() => _PicturesReadyState();
}

class _PicturesReadyState extends State<PicturesReady> {
  /// The pictures last asked for; an answer for older ones is dropped.
  List<ImageProvider>? _asked;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked == null) _ask();
  }

  @override
  void didUpdateWidget(PicturesReady oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(widget.pictures, _asked)) return;
    _ready = false;
    _ask();
  }

  void _ask() {
    final pictures = _asked = widget.pictures;
    Future.wait([
      for (final picture in pictures)
        precacheImage(picture, context, onError: (_, _) {}),
    ]).then((_) {
      if (mounted && identical(_asked, pictures)) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
