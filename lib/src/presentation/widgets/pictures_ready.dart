import 'package:flutter/widgets.dart';

/// Builds [child] once every one of [pictures] has loaded or failed to, and
/// nothing before.
///
/// Pictures that make up one look, such as the corners of a profile frame or
/// the intro and loop of a profile effect, then appear together and play
/// from their start, instead of one by one as each arrives. A picture that
/// fails does not hold the rest back.
class PicturesReady extends StatefulWidget {
  const PicturesReady({required this.pictures, required this.child, super.key});

  final List<ImageProvider> pictures;
  final Widget child;

  @override
  State<PicturesReady> createState() => _PicturesReadyState();
}

class _PicturesReadyState extends State<PicturesReady> {
  bool _asked = false;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    Future.wait([
      for (final picture in widget.pictures)
        precacheImage(picture, context, onError: (_, _) {}),
    ]).then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
