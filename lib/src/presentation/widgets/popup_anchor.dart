import 'package:flutter/material.dart';

/// The rectangle of the widget at [context], in the coordinates of the
/// navigator that menus and popups open in.
Rect popupAnchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// Where a menu opened from the widget at [context] goes: just under it.
RelativeRect menuBelow(BuildContext context) {
  final anchor = popupAnchorOf(context);
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromLTWH(anchor.left, anchor.bottom + 4, anchor.width, 0),
    Offset.zero & overlay.size,
  );
}
