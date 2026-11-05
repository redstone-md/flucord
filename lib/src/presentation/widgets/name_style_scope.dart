import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../data/discord/display_name_fonts.dart';
import 'nameplate_motion.dart';

/// What names and nameplates below it need beyond their data: the one
/// moving nameplate, the clock moving names are drawn at, and the loader for
/// Discord's name fonts.
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

  /// The clock moving names are drawn at, or null without a scope.
  static NameClock? clockOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NameStyles>()?.clock;

  @override
  State<NameStyleScope> createState() => _NameStyleScopeState();
}

class _NameStyleScopeState extends State<NameStyleScope>
    with SingleTickerProviderStateMixin {
  late final _motion = NameplateMotion(widget.videos);
  late final _clock = NameClock._(this);

  @override
  void dispose() {
    _motion.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _NameStyles(
    motion: _motion,
    clock: _clock,
    fonts: widget.fonts,
    child: widget.child,
  );
}

/// One ticker for every moving name, so a list of them costs one frame
/// callback. It runs only while a name listens: a name listens only while it
/// moves, and the motion rule mutes the ticker for a window nobody looks at.
final class NameClock extends ChangeNotifier {
  NameClock._(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  int _listeners = 0;

  /// The time already run when the ticker last stopped.
  Duration _before = Duration.zero;
  Duration _now = Duration.zero;

  /// How long names have been moving, in all.
  Duration get now => _now;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_listeners++ == 0) _ticker.start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (--_listeners == 0) {
      _ticker.stop();
      _before = _now;
    }
  }

  void _tick(Duration elapsed) {
    _now = _before + elapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Rebuilds the names below it each time a font is ready.
class _NameStyles extends InheritedNotifier<DisplayNameFonts> {
  const _NameStyles({
    required this.motion,
    required this.clock,
    required DisplayNameFonts fonts,
    required super.child,
  }) : super(notifier: fonts);

  final NameplateMotion motion;
  final NameClock clock;

  DisplayNameFonts get fonts => notifier!;

  @override
  bool updateShouldNotify(_NameStyles oldWidget) =>
      motion != oldWidget.motion || super.updateShouldNotify(oldWidget);
}
