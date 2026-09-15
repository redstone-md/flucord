import 'package:flutter/material.dart';

import '../../application/accessibility_controller.dart';
import '../../domain/accessibility.dart';
import '../../theme/flucord_theme.dart';

/// The interface adjustments: font scale, zoom, reduced motion and the
/// local spellcheck switch.
///
/// Each dial changes the interface as it is dragged: the whole point is
/// being able to see what a value does before committing to it.
class AccessibilitySection extends StatelessWidget {
  const AccessibilitySection({required this.controller, super.key});

  final AccessibilityController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      key: const ValueKey('accessibility-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Dial(
          dialKey: const ValueKey('accessibility-font-scale'),
          title: 'Font scale',
          subtitle: 'Resizes every piece of text in the app.',
          min: AccessibilitySettings.minFontScale,
          max: AccessibilitySettings.maxFontScale,
          value: controller.fontScale,
          onChanged: controller.setFontScale,
        ),
        _Dial(
          dialKey: const ValueKey('accessibility-zoom'),
          title: 'Zoom',
          subtitle: 'Scales the whole interface.',
          min: AccessibilitySettings.minZoom,
          max: AccessibilitySettings.maxZoom,
          value: controller.zoom,
          onChanged: controller.setZoom,
        ),
        _Switch(
          switchKey: const ValueKey('accessibility-reduced-motion'),
          title: 'Reduced motion',
          subtitle: 'Animations hold their end state instead of playing.',
          value: controller.reducesMotion,
          onChanged: (value) => controller.setReducedMotion(reduced: value),
        ),
        _Switch(
          switchKey: const ValueKey('accessibility-spellcheck'),
          title: 'Spellcheck',
          subtitle:
              'Underlines words the local dictionary does not know. '
              'Nothing leaves the app.',
          value: controller.spellchecks,
          onChanged: (value) => controller.setSpellcheck(enabled: value),
        ),
        if (controller.writeError case final error?)
          Padding(
            key: const ValueKey('accessibility-write-error'),
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'The change is on screen but was not saved: $error',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.dialKey,
    required this.title,
    required this.subtitle,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final Key dialKey;
  final String title;
  final String subtitle;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
          Text(
            // A percentage reads better than a bare ratio on a dial.
            '${(value * 100).round()}%',
            style: TextStyle(fontSize: 11, color: context.surfaces.muted),
          ),
        ],
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          key: dialKey,
          min: min,
          max: max,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: context.surfaces.muted),
        ),
      ),
    ],
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: switchKey,
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: onChanged,
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 11, color: context.surfaces.muted),
    ),
  );
}
