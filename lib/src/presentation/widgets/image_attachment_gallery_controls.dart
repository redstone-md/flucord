part of 'image_attachment_viewer.dart';

class _GalleryNavigationButton extends StatelessWidget {
  const _GalleryNavigationButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Container(
      width: 40,
      height: 48,
      decoration: BoxDecoration(
        color: context.surfaces.surface.withValues(
          alpha: onPressed == null ? 0.48 : 0.92,
        ),
        border: Border.all(
          color: context.surfaces.border.withValues(
            alpha: onPressed == null ? 0.48 : 1,
          ),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 48),
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
      ),
    ),
  );
}

class _GalleryCounter extends StatelessWidget {
  const _GalleryCounter({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      key: const ValueKey('image-viewer-counter'),
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaces.surface.withValues(alpha: 0.92),
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${index + 1} / $total',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}
