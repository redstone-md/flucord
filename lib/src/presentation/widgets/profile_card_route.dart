import 'package:flutter/material.dart';

import 'popup_anchor.dart';

/// Opens somebody's profile card beside the thing that was clicked: the
/// person's id, and that thing's rectangle from [popupAnchorOf].
typedef OpenProfileCard = void Function(String userId, Rect anchor);

/// Shows the card [builder] makes beside [anchor], and completes when it
/// closes. A click outside or Escape closes it; [builder] gets a callback
/// that does the same.
Future<void> showProfileCard({
  required BuildContext context,
  required Rect anchor,
  required Widget Function(VoidCallback close) builder,
}) => Navigator.of(
  context,
).push(_ProfileCardRoute(anchor: anchor, builder: builder));

final class _ProfileCardRoute extends PopupRoute<void> {
  _ProfileCardRoute({required this.anchor, required this.builder});

  final Rect anchor;
  final Widget Function(VoidCallback close) builder;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Close profile';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

  // Closing is instant, as Discord's popout is.
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _BesideAnchor(anchor),
    child: builder(_close),
  );

  /// Closes the card even with a menu or a dialog it opened still on top.
  void _close() {
    if (isCurrent) {
      navigator!.pop();
    } else if (isActive) {
      navigator!.removeRoute(this);
    }
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// Puts the card on whichever side of the anchor has room, preferring the
/// side away from the screen edge the anchor is near, with its top level
/// with the anchor's and the whole card on screen.
final class _BesideAnchor extends SingleChildLayoutDelegate {
  const _BesideAnchor(this.anchor);

  static const _gap = 8.0;
  static const _margin = 8.0;

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        constraints.biggest,
      ).deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + _gap;
    final left = anchor.left - _gap - childSize.width;
    final fitsRight = right + childSize.width <= size.width - _margin;
    final fitsLeft = left >= _margin;
    final goRight = anchor.center.dx < size.width / 2
        ? fitsRight || !fitsLeft
        : fitsRight && !fitsLeft;
    final x = goRight ? right : left;
    double clamp(double value, double extent, double room) =>
        value.clamp(_margin, (room - _margin - extent).clamp(_margin, room));
    return Offset(
      clamp(x, childSize.width, size.width),
      clamp(anchor.top, childSize.height, size.height),
    );
  }

  @override
  bool shouldRelayout(_BesideAnchor oldDelegate) =>
      anchor != oldDelegate.anchor;
}
