import 'package:flutter/widgets.dart';

final class AnchoredScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => AnchoredScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
  );

  void shiftBy(double displacement) {
    if (!hasClients || displacement.abs() <= 0.5) return;
    (position as AnchoredScrollPosition).shiftBy(displacement);
  }
}

final class AnchoredScrollPosition extends ScrollPositionWithSingleContext {
  AnchoredScrollPosition({
    required super.physics,
    required super.context,
    required super.oldPosition,
    required super.keepScrollOffset,
    required super.debugLabel,
  });

  void shiftBy(double displacement) {
    goIdle();
    forcePixels(pixels + displacement);
  }
}
