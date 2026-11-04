import 'package:flutter/widgets.dart';

import '../../data/discord/display_name_fonts.dart';
import 'nameplate_motion.dart';

/// What names and nameplates below it need beyond their data: the one
/// moving nameplate, and the loader for Discord's name fonts.
///
/// Without this scope above them, nameplates stay still and names keep the
/// app font. Widget tests that do not care about either leave it out.
class NameStyleScope extends StatefulWidget {
  const NameStyleScope({
    required this.videos,
    required this.fonts,
    required this.child,
    super.key,
  });

  final NameplateVideos videos;
  final DisplayNameFonts fonts;
  final Widget child;

  static NameplateMotion? motionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NameStyles>()?.motion;

  static DisplayNameFonts? fontsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NameStyles>()?.fonts;

  @override
  State<NameStyleScope> createState() => _NameStyleScopeState();
}

class _NameStyleScopeState extends State<NameStyleScope> {
  late final _motion = NameplateMotion(widget.videos);

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NameStyles(motion: _motion, fonts: widget.fonts, child: widget.child);
}

class _NameStyles extends InheritedWidget {
  const _NameStyles({
    required this.motion,
    required this.fonts,
    required super.child,
  });

  final NameplateMotion motion;
  final DisplayNameFonts fonts;

  @override
  bool updateShouldNotify(_NameStyles oldWidget) =>
      motion != oldWidget.motion || fonts != oldWidget.fonts;
}
