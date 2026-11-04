import 'package:flutter/widgets.dart';

import '../../application/window_visible.dart';

/// The one motion rule: whether decorative animation may run now.
///
/// Every ticker below stops while the window is **unfocused** or
/// **suspended** (CONTEXT.md), so GIFs, animated emoji, Lottie stickers and
/// spinners draw no frames for a window nobody is looking at. Flutter's
/// [Image] and every [AnimationController] already follow [TickerMode], and
/// [Image] follows reduced motion as well.
///
/// Watched sessions and cameras draw through textures, not tickers, and keep
/// their own rule (ADR-0003).
class MotionScope extends StatelessWidget {
  const MotionScope({required this.window, required this.child, super.key});

  final WindowVisible window;
  final Widget child;

  /// Whether decorative animation may run at [context]: the window is looked
  /// at and reduced motion is off. Reading it makes [context] rebuild when
  /// the answer changes.
  static bool allows(BuildContext context) =>
      TickerMode.valuesOf(context).enabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: window,
    builder: (_, child) =>
        TickerMode(enabled: window.isLookedAt, child: child!),
    child: child,
  );
}

/// The row, message or card whose hover plays the animated pictures inside
/// it, such as avatars and status emoji. Discord plays them only while the
/// pointer is on what holds them, so an idle list draws no frames.
class MotionHoverRegion extends StatefulWidget {
  const MotionHoverRegion({required this.child, super.key});

  final Widget child;

  /// Whether the pointer is on the region around [context], or null when
  /// there is none. Reading it makes [context] rebuild on enter and exit.
  static bool? hoveredOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_HoverScope>()
      ?.notifier
      ?.value;

  @override
  State<MotionHoverRegion> createState() => _MotionHoverRegionState();
}

class _MotionHoverRegionState extends State<MotionHoverRegion> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hovered.value = true,
    onExit: (_) => _hovered.value = false,
    child: _HoverScope(notifier: _hovered, child: widget.child),
  );
}

class _HoverScope extends InheritedNotifier<ValueNotifier<bool>> {
  const _HoverScope({required super.notifier, required super.child});
}
