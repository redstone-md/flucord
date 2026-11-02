import 'dart:math';

import 'package:flutter/material.dart';

import '../../application/accessibility_controller.dart';
import 'accessibility_scope.dart';

/// Applies the zoom, font and motion dials to everything below it.
///
/// It sits in the app builder, above the navigator, so dialogs and menus get
/// the dials too. The child lays out at the window size divided by zoom and is
/// then drawn scaled up to fill the window, so panes and breakpoints see the
/// smaller space and nothing is drawn off screen.
///
/// One catch for the code below: a global position is in window pixels, and an
/// overlay is in zoomed pixels. Convert with `globalToLocal` on the overlay, or
/// pass `ancestor` to `localToGlobal`, before comparing the two.
class AccessibilityDials extends StatelessWidget {
  const AccessibilityDials({
    required this.controller,
    required this.child,
    super.key,
  });

  final AccessibilityController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoom = controller.zoom;
    final window = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final laidOutSize = constraints.biggest / zoom;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: laidOutSize,
            child: MediaQuery(
              data: window.copyWith(
                size: laidOutSize,
                // Pictures are decoded for the pixels they really cover.
                devicePixelRatio: window.devicePixelRatio * zoom,
                textScaler: TextScaler.linear(controller.fontScale),
                disableAnimations: controller.reducesMotion,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The height a popup with a set size may use: what it wants, or what the
/// window has when zoom or a small window leaves less.
double heightWithinWindow(BuildContext context, double wanted) =>
    min(wanted, MediaQuery.sizeOf(context).height - 16);

/// A text field's copy and paste menu, placed at the pointer under zoom.
///
/// Pass it as `contextMenuBuilder`. Flutter gives the menu an anchor in window
/// pixels, then moves the menu back by the field's corner, also in window
/// pixels, inside a space that is zoomed. So the anchor is converted to zoomed
/// pixels, which keeps the menu's own fit-on-screen check right, and the
/// translation makes up for the difference at the corner.
Widget zoomedTextFieldMenu(BuildContext context, EditableTextState field) {
  final zoom = AccessibilityScope.maybeOf(context)?.zoom ?? 1;
  final corner = field.renderEditable.localToGlobal(Offset.zero);
  final anchors = field.contextMenuAnchors;
  return Transform.translate(
    offset: corner - corner / zoom,
    child: AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: anchors.primaryAnchor / zoom,
        secondaryAnchor: switch (anchors.secondaryAnchor) {
          final secondary? => secondary / zoom,
          null => null,
        },
      ),
      buttonItems: field.contextMenuButtonItems,
    ),
  );
}
