import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Answers a request from inside [child] to be shown, such as a text
/// field's caret, with [onReveal] instead of passing it on to the scroll
/// views above.
///
/// The timeline needs this: Flutter's own reveal works out the wrong offset
/// for a row in the part of the list that grows upward, and scrolled an
/// edited message out of view the moment its field took the focus.
class RevealBoundary extends SingleChildRenderObjectWidget {
  const RevealBoundary({
    required this.onReveal,
    required super.child,
    super.key,
  });

  final VoidCallback onReveal;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRevealBoundary(onReveal);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRevealBoundary renderObject,
  ) => renderObject.onReveal = onReveal;
}

class RenderRevealBoundary extends RenderProxyBox {
  RenderRevealBoundary(this.onReveal);

  VoidCallback onReveal;

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) => onReveal();
}

/// Scrolls the nearest scroll view above [context] just enough to show the
/// whole of its box, the top first when it is taller than the view.
void revealInScrollable(BuildContext context) {
  final scrollable = Scrollable.maybeOf(context);
  final box = context.findRenderObject();
  final view = scrollable?.context.findRenderObject();
  if (scrollable == null ||
      box is! RenderBox ||
      !box.hasSize ||
      view is! RenderBox) {
    return;
  }
  final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
  final bottom = top + box.size.height;
  final height = view.size.height;
  final delta = top < 0
      ? top
      : bottom > height
      ? (bottom - height).clamp(0.0, top)
      : 0.0;
  if (delta == 0) return;
  final position = scrollable.position;
  position.jumpTo(
    (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ),
  );
}
