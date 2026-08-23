import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/stream_quality_controller.dart';
import '../../theme/flucord_theme.dart';

/// The step both sliders commit on: fine enough to mean what the label says,
/// coarse enough that the stored number stays readable.
const _step = 50000.0;

/// Stream quality: the bitrates a share and a camera are encoded at.
///
/// Discord's web client caps a share at 2.5 Mbit; a desktop client may use
/// more, so the bitrates are a setting rather than a policy baked into the
/// capture module. A change does not touch a capture that is already running:
/// the encoder runs one set of settings at a time.
class StreamQualitySection extends StatelessWidget {
  const StreamQualitySection({required this.controller, super.key});

  final StreamQualityController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      key: const ValueKey('stream-quality-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What this machine sends its pictures at. Applies the next time a '
          'share or a camera starts.',
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _BitrateSlider(
          sliderKey: const ValueKey('stream-quality-share'),
          label: 'Screen share bitrate',
          subtitle: 'A share of a desktop full of text needs the larger part.',
          bitrate: controller.shareBitrate,
          min: _shareMin,
          max: _shareMax,
          divisions: _divisionsFor(_shareMin, _shareMax),
          onChanged: controller.setShareBitrate,
        ),
        const SizedBox(height: 14),
        _BitrateSlider(
          sliderKey: const ValueKey('stream-quality-camera'),
          label: 'Camera bitrate',
          subtitle: 'A webcam picture carries less detail than a desktop.',
          bitrate: controller.cameraBitrate,
          min: _cameraMin,
          max: _cameraMax,
          divisions: _divisionsFor(_cameraMin, _cameraMax),
          onChanged: controller.setCameraBitrate,
        ),
        if (controller.writeError != null)
          Padding(
            key: const ValueKey('stream-quality-write-error'),
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // Said out loud: the change still applies until the client is
              // restarted, and pretending it was kept is how a setting turns
              // out to have never been one.
              'Could not save the change: it applies now, but the next '
              'restart forgets it.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    ),
  );

  /// The range the picker offers. Generous rather than clever: a bitrate above
  /// it is still accepted from the file, it just cannot be picked here.
  static const _shareMin = 1000000.0;
  static const _shareMax = 10000000.0;
  static const _cameraMin = 400000.0;
  static const _cameraMax = 4000000.0;

  static int _divisionsFor(double min, double max) =>
      ((max - min) / _step).round();
}

class _BitrateSlider extends StatefulWidget {
  const _BitrateSlider({
    required this.sliderKey,
    required this.label,
    required this.subtitle,
    required this.bitrate,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final String subtitle;
  final int bitrate;
  final double min;
  final double max;
  final int divisions;
  final Future<void> Function(int) onChanged;

  @override
  State<_BitrateSlider> createState() => _BitrateSliderState();
}

class _BitrateSliderState extends State<_BitrateSlider> {
  /// The value under the thumb while it is being dragged, so the label can
  /// show what a release would commit without committing on every pixel.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    // A stored bitrate outside the picker's range (the file was edited by
    // hand) still has to draw: the slider clamps it to the track, while the
    // label reads the stored number itself and keeps telling the truth.
    final value =
        _dragging ?? widget.bitrate.clamp(widget.min, widget.max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              _inMegabits((_dragging ?? widget.bitrate).toDouble()),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            key: widget.sliderKey,
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: _inMegabits(value),
            onChanged: (next) => setState(() => _dragging = next),
            onChangeEnd: (next) {
              setState(() => _dragging = null);
              // Snapped against the bottom of the range, so any minimum lands
              // on a step rather than only the ones that divide evenly.
              final steps = ((next - widget.min) / _step).round();
              final committed = (widget.min + steps * _step).round();
              unawaited(widget.onChanged(committed));
            },
          ),
        ),
        Text(
          widget.subtitle,
          style: TextStyle(fontSize: 11, color: context.surfaces.muted),
        ),
      ],
    );
  }

  static String _inMegabits(double bitsPerSecond) =>
      '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mbit';
}
