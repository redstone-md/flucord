import 'package:flutter/material.dart';

import '../../domain/voice_media.dart';
import '../../theme/flucord_theme.dart';

/// The screen and window picker Go Live opens.
///
/// Split out of the voice room because it is a modal with its own lifetime: the
/// room rebuilds on every speaking flag and device change, and none of that has
/// anything to say about a dialog the user is already looking at.
class VoiceCaptureSourceDialog extends StatelessWidget {
  const VoiceCaptureSourceDialog({required this.sources, super.key});

  final List<VoiceCaptureSource> sources;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share a screen or window'),
      content: SizedBox(
        width: 680,
        height: 430,
        child: sources.isEmpty
            ? const Center(child: Text('No capture sources available'))
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 150,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return InkWell(
                    key: ValueKey('capture-source-${source.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.pop(context, source),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.surfaces.inset,
                        border: Border.all(color: context.surfaces.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: source.thumbnail == null
                                ? const Icon(Icons.desktop_windows_outlined)
                                : ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                    child: Image.memory(
                                      source.thumbnail!,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              source.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
