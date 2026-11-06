import 'package:flutter/material.dart';

/// The rectangle of the widget at [context], in the coordinates of the
/// navigator that menus and popups open in.
Rect popupAnchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// Where a context menu opened from the widget at [context] goes: at
/// [position], in global coordinates, for a click; in the widget's middle
/// when null, as for the context-menu key.
RelativeRect menuAt(BuildContext context, {Offset? position}) {
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()!
          as RenderBox;
  final source = context.findRenderObject()! as RenderBox;
  final at = overlay.globalToLocal(
    position ?? source.localToGlobal(source.size.center(Offset.zero)),
  );
  return RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size);
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
