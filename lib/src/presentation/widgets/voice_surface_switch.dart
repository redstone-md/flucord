import 'package:flutter/material.dart';

import '../../application/voice_channel_surface.dart';
import '../../theme/flucord_theme.dart';

/// Segmented control that swaps a voice channel between its room and its
/// message timeline.
///
/// It is a pair of real buttons rather than an icon that silently toggles: both
/// destinations stay named and visible, both take keyboard focus in the header's
/// traversal order, and the selected one is announced through [Semantics] so the
/// current surface is legible without colour. Labels collapse to bare icons in
/// narrow windows so the header never has to overflow to keep the control.
class VoiceSurfaceSwitch extends StatelessWidget {
  const VoiceSurfaceSwitch({
    required this.surface,
    required this.onChanged,
    this.showLabels = true,
    super.key,
  });

  final VoiceChannelSurface surface;
  final ValueChanged<VoiceChannelSurface> onChanged;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('voice-surface-switch'),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SurfaceSegment(
              value: VoiceChannelSurface.room,
              selected: surface == VoiceChannelSurface.room,
              icon: Icons.volume_up_outlined,
              label: 'Voice',
              tooltip: 'Voice room',
              showLabel: showLabels,
              onPressed: onChanged,
            ),
            const SizedBox(width: 2),
            _SurfaceSegment(
              value: VoiceChannelSurface.chat,
              selected: surface == VoiceChannelSurface.chat,
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              tooltip: 'Channel chat',
              showLabel: showLabels,
              onPressed: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceSegment extends StatelessWidget {
  const _SurfaceSegment({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.showLabel,
    required this.onPressed,
  });

  final VoiceChannelSurface value;
  final bool selected;
  final IconData icon;
  final String label;
  final String tooltip;
  final bool showLabel;
  final ValueChanged<VoiceChannelSurface> onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Theme.of(context).colorScheme.onSurface
        : context.surfaces.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? context.surfaces.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: ValueKey('voice-surface-${value.name}'),
            onTap: () => onPressed(value),
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: showLabel ? 10 : 8,
                vertical: 5,
              ),
              // The visible label repeats what [Semantics] already announces,
              // so it is excluded to keep the reading short.
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: foreground),
                    if (showLabel) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
