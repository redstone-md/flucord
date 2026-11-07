import 'package:flutter/material.dart';

import '../../domain/stream_captures.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_controls.dart';
import 'flucord_dialog.dart';

/// Takes a thumbnail of each source, by source id.
typedef ShareThumbnails =
    Future<Map<String, CaptureThumbnail>> Function(List<StreamCapture> sources);

enum _Tab { applications, screens }

/// What to share: a window or a whole screen, each shown with a thumbnail.
///
/// Laid out like Discord's picker: Applications and Screens tabs, opening on
/// Applications. The thumbnails are taken once, when the picker opens. Each
/// display capture behind them is closed before the picker answers, because
/// Windows allows one duplication of an output at a time and a thumbnail
/// still holding one would refuse the share that follows.
class GoLiveSourceDialog extends StatefulWidget {
  const GoLiveSourceDialog({
    required this.sources,
    required this.thumbnails,
    super.key,
  });

  final List<StreamCapture> sources;
  final ShareThumbnails thumbnails;

  /// Asks which of [sources] to share, answering its source id, or null when
  /// dismissed. One screen and no window is shared without asking.
  static Future<String?> pick(
    BuildContext context, {
    required List<StreamCapture> sources,
    required ShareThumbnails thumbnails,
  }) async {
    if (sources.length <= 1) return sources.firstOrNull?.sourceId;
    return showDialog<String>(
      context: context,
      builder: (_) =>
          GoLiveSourceDialog(sources: sources, thumbnails: thumbnails),
    );
  }

  @override
  State<GoLiveSourceDialog> createState() => _GoLiveSourceDialogState();
}

class _GoLiveSourceDialogState extends State<GoLiveSourceDialog> {
  late final Future<Map<String, CaptureThumbnail>> _thumbnails = widget
      .thumbnails(widget.sources)
      .catchError((Object _) => <String, CaptureThumbnail>{});

  late final List<WindowCapture> _windows = [
    for (final source in widget.sources)
      if (source is WindowCapture) source,
  ];
  late final List<DisplayCapture> _screens = [
    for (final source in widget.sources)
      if (source is DisplayCapture) source,
  ];

  late _Tab _tab = _windows.isEmpty ? _Tab.screens : _Tab.applications;
  bool _picking = false;

  Future<void> _pick(StreamCapture source) async {
    if (_picking) return;
    setState(() => _picking = true);
    await _thumbnails;
    if (mounted) Navigator.of(context).pop(source.sourceId);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _tab == _Tab.applications ? _windows : _screens;
    return FlucordDialog(
      key: const ValueKey('go-live-source-dialog'),
      title: const Text('Share your screen'),
      maxWidth: 600,
      content: widget.sources.isEmpty
          ? const Text('This machine reported no screen to capture.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_windows.isNotEmpty) ...[
                  FlucordSegmented<_Tab>(
                    keyPrefix: 'go-live-tab',
                    options: const [
                      FlucordSegment(_Tab.applications, 'Applications'),
                      FlucordSegment(_Tab.screens, 'Screens'),
                    ],
                    selected: _tab,
                    onSelected: (tab) => setState(() => _tab = tab),
                  ),
                  const SizedBox(height: 12),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: FutureBuilder(
                    future: _thumbnails,
                    builder: (context, snapshot) => SingleChildScrollView(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final source in shown)
                            _SourceTile(
                              source: source,
                              thumbnail: snapshot.data?[source.sourceId],
                              onPressed: _picking ? null : () => _pick(source),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      actions: const [FlucordDialogCancel()],
    );
  }
}

/// One source: its thumbnail, or its icon while there is none, over its name.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.thumbnail,
    required this.onPressed,
  });

  final StreamCapture source;
  final CaptureThumbnail? thumbnail;
  final VoidCallback? onPressed;

  static const double _width = 176;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final thumbnail = this.thumbnail;
    return SizedBox(
      width: _width,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('go-live-source-${source.sourceId}'),
          onTap: onPressed,
          borderRadius: FlucordRadius.medium,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surfaces.inset,
                      borderRadius: FlucordRadius.control,
                      border: Border.all(color: surfaces.border),
                    ),
                    child: ClipRRect(
                      borderRadius: FlucordRadius.control,
                      child: thumbnail == null
                          ? Center(
                              child: FlucordIcon(
                                source is WindowCapture
                                    ? FlucordIcons.appWindow
                                    : FlucordIcons.desktop,
                                color: surfaces.muted,
                              ),
                            )
                          : Image.memory(
                              thumbnail.bytes,
                              key: ValueKey(
                                'go-live-thumbnail-${source.sourceId}',
                              ),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlucordTextRole.label.style.copyWith(
                    color: surfaces.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
