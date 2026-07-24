import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../attachment_download_controller.dart';
import 'attachment_download_button.dart';

class ImageAttachmentViewer extends StatefulWidget {
  const ImageAttachmentViewer({
    required this.attachment,
    required this.onClose,
    this.downloadController,
    this.imageBuilder,
    super.key,
  });

  final MessageAttachment attachment;
  final VoidCallback onClose;
  final AttachmentDownloadController? downloadController;
  final WidgetBuilder? imageBuilder;

  static Future<void> show(
    BuildContext context, {
    required MessageAttachment attachment,
    AttachmentDownloadController? downloadController,
    WidgetBuilder? imageBuilder,
  }) async {
    final previousFocus = FocusManager.instance.primaryFocus;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close image viewer',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (routeContext, _, _) => ImageAttachmentViewer(
        attachment: attachment,
        downloadController: downloadController,
        imageBuilder: imageBuilder,
        onClose: () => Navigator.of(routeContext).pop(),
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
    if (context.mounted && (previousFocus?.canRequestFocus ?? false)) {
      previousFocus!.requestFocus();
    }
  }

  @override
  State<ImageAttachmentViewer> createState() => _ImageAttachmentViewerState();
}

class _ImageAttachmentViewerState extends State<ImageAttachmentViewer> {
  static const double _minScale = 0.5;
  static const double _maxScale = 5;
  static const double _zoomStep = 1.25;

  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    label: 'Image viewer · ${widget.attachment.fileName}',
    explicitChildNodes: true,
    child: Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _CloseImageIntent(),
        SingleActivator(LogicalKeyboardKey.equal, control: true):
            _ZoomImageIntent(true),
        SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
            _ZoomImageIntent(true),
        SingleActivator(LogicalKeyboardKey.minus, control: true):
            _ZoomImageIntent(false),
        SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _ResetImageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CloseImageIntent: CallbackAction<_CloseImageIntent>(
            onInvoke: (_) {
              widget.onClose();
              return null;
            },
          ),
          _ZoomImageIntent: CallbackAction<_ZoomImageIntent>(
            onInvoke: (intent) {
              _zoom(intent.zoomIn);
              return null;
            },
          ),
          _ResetImageIntent: CallbackAction<_ResetImageIntent>(
            onInvoke: (_) {
              _reset();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            key: const ValueKey('image-attachment-viewer'),
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  top: 48,
                  child: GestureDetector(
                    onDoubleTap: _reset,
                    child: InteractiveViewer(
                      key: const ValueKey('image-viewer-canvas'),
                      transformationController: _transformationController,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      boundaryMargin: const EdgeInsets.all(160),
                      onInteractionUpdate: (_) => _readScale(),
                      onInteractionEnd: (_) => _readScale(),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child:
                              widget.imageBuilder?.call(context) ??
                              _NetworkViewerImage(
                                attachment: widget.attachment,
                                canSave: widget.downloadController != null,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: _ViewerToolbar(
                    attachment: widget.attachment,
                    scale: _scale,
                    downloadController: widget.downloadController,
                    onZoomOut: () => _zoom(false),
                    onReset: _reset,
                    onZoomIn: () => _zoom(true),
                    onClose: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _readScale() {
    final next = _transformationController.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() < 0.005 || !mounted) return;
    setState(() => _scale = next);
  }

  void _zoom(bool zoomIn) {
    final target = (_scale * (zoomIn ? _zoomStep : 1 / _zoomStep)).clamp(
      _minScale,
      _maxScale,
    );
    final matrix = Matrix4.diagonal3Values(target, target, 1);
    _transformationController.value = matrix;
    setState(() => _scale = target);
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
    if (_scale != 1) setState(() => _scale = 1);
  }
}

class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.attachment,
    required this.scale,
    required this.downloadController,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
    required this.onClose,
  });

  final MessageAttachment attachment;
  final double scale;
  final AttachmentDownloadController? downloadController;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 460;
      final veryCompact = constraints.maxWidth < 340;
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.surfaces.surface.withValues(alpha: 0.96),
          border: Border(bottom: BorderSide(color: context.surfaces.border)),
        ),
        child: Row(
          children: [
            if (!veryCompact) ...[
              const Icon(Icons.image_outlined, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!compact && attachment.width != null) ...[
              const SizedBox(width: 8),
              Text(
                '${attachment.width}×${attachment.height ?? '?'}',
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ],
            SizedBox(width: compact ? 4 : 12),
            _ToolbarButton(
              key: const ValueKey('image-viewer-zoom-out'),
              icon: Icons.remove,
              tooltip: 'Zoom out · Ctrl+-',
              onPressed: onZoomOut,
            ),
            SizedBox(
              width: 52,
              child: TextButton(
                key: const ValueKey('image-viewer-reset'),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onReset,
                child: Text('${(scale * 100).round()}%'),
              ),
            ),
            _ToolbarButton(
              key: const ValueKey('image-viewer-zoom-in'),
              icon: Icons.add,
              tooltip: 'Zoom in · Ctrl++',
              onPressed: onZoomIn,
            ),
            if (downloadController case final controller?) ...[
              const SizedBox(width: 4),
              AttachmentDownloadButton(
                controller: controller,
                overlaid: true,
                keyPrefix: 'image-viewer-attachment',
              ),
            ],
            const SizedBox(width: 4),
            _ToolbarButton(
              key: const ValueKey('image-viewer-close'),
              icon: Icons.close,
              tooltip: 'Close · Esc',
              onPressed: onClose,
            ),
          ],
        ),
      );
    },
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    iconSize: 18,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

class _NetworkViewerImage extends StatelessWidget {
  const _NetworkViewerImage({required this.attachment, required this.canSave});

  final MessageAttachment attachment;
  final bool canSave;

  @override
  Widget build(BuildContext context) => Image.network(
    attachment.url,
    key: ValueKey('image-viewer-image-${attachment.id}'),
    fit: BoxFit.contain,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : Stack(
            alignment: Alignment.center,
            children: [
              child,
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
    errorBuilder: (_, _, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: context.surfaces.muted,
          ),
          const SizedBox(height: 8),
          const Text('Preview unavailable'),
          if (canSave) ...[
            const SizedBox(height: 4),
            Text(
              'The original attachment can still be saved.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CloseImageIntent extends Intent {
  const _CloseImageIntent();
}

class _ZoomImageIntent extends Intent {
  const _ZoomImageIntent(this.zoomIn);

  final bool zoomIn;
}

class _ResetImageIntent extends Intent {
  const _ResetImageIntent();
}
