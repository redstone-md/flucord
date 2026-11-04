part of 'flucord_shell.dart';

/// The card that holds the work area: chat, the side panels and the member
/// list. Everything to its left is navigation, drawn on the rail colour that
/// also shows through the inset around the card, in the [NavigationTheme].
///
/// The border is drawn on top of the content, so a panel that paints its own
/// background cannot cover it, even at the rounded corners.
class _CanvasCard extends StatelessWidget {
  const _CanvasCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return ColoredBox(
      color: NavigationTheme.surfacesOf(context).rail,
      child: Padding(
        padding: const EdgeInsets.only(
          top: FlucordTheme.canvasInset,
          right: FlucordTheme.canvasInset,
          bottom: FlucordTheme.canvasInset,
        ),
        child: Container(
          key: const ValueKey('canvas-card'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surfaces.canvas,
            borderRadius: FlucordRadius.large,
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: surfaces.border),
            borderRadius: FlucordRadius.large,
          ),
          child: child,
        ),
      ),
    );
  }
}
