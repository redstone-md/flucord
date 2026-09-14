import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../theme/flucord_theme.dart';

typedef InlineVoiceBuilder =
    Widget Function({
      required String url,
      required Duration? duration,
      required String? waveform,
      Key? key,
    });

Widget buildNativeVoiceMessage({
  required String url,
  required Duration? duration,
  required String? waveform,
  Key? key,
}) => NativeVoiceMessagePlayer(
  key: key,
  url: url,
  expectedDuration: duration,
  waveform: waveform,
);

final class VoiceMessageViewState {
  const VoiceMessageViewState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = true,
    this.isCompleted = false,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;

  VoiceMessageViewState copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
  }) => VoiceMessageViewState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    isCompleted: isCompleted ?? this.isCompleted,
  );
}

abstract final class DiscordVoiceWaveform {
  static List<double> decode(String? source) {
    if (source == null || source.isEmpty) return const [];
    try {
      final bytes = base64Decode(base64.normalize(source));
      return List<double>.unmodifiable(
        bytes.map((value) => math.max(0.08, value / 255)),
      );
    } on FormatException {
      return const [];
    }
  }
}

class NativeVoiceMessagePlayer extends StatefulWidget {
  const NativeVoiceMessagePlayer({
    required this.url,
    required this.expectedDuration,
    required this.waveform,
    super.key,
  });

  final String url;
  final Duration? expectedDuration;
  final String? waveform;

  @override
  State<NativeVoiceMessagePlayer> createState() =>
      _NativeVoiceMessagePlayerState();
}

class _NativeVoiceMessagePlayerState extends State<NativeVoiceMessagePlayer> {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Player? _player;
  late VoiceMessageViewState _viewState;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _viewState = _initialState;
    _initialize();
  }

  VoiceMessageViewState get _initialState =>
      VoiceMessageViewState(duration: widget.expectedDuration ?? Duration.zero);

  @override
  void didUpdateWidget(covariant NativeVoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initialize();
    } else if (oldWidget.expectedDuration != widget.expectedDuration &&
        _viewState.duration == Duration.zero) {
      setState(() {
        _viewState = _viewState.copyWith(
          duration: widget.expectedDuration ?? Duration.zero,
        );
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_release());
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    await _release();
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = null;
      _viewState = _initialState;
    });
    try {
      final player = Player();
      _player = player;
      _bind(player, generation);
      await player.open(Media(widget.url), play: false);
      if (!mounted || generation != _generation) return;
      setState(() {
        _viewState = _viewState.copyWith(isBuffering: player.state.buffering);
      });
    } catch (error) {
      _setError(error, generation);
    }
  }

  void _bind(Player player, int generation) {
    _subscriptions.addAll([
      player.stream.playing.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(isPlaying: value)),
      ),
      player.stream.position.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(position: value)),
      ),
      player.stream.duration.listen((value) {
        if (value == Duration.zero) return;
        _update(generation, (state) => state.copyWith(duration: value));
      }),
      player.stream.buffering.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(isBuffering: value)),
      ),
      player.stream.completed.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(isCompleted: value)),
      ),
      player.stream.error.listen((value) => _setError(value, generation)),
    ]);
  }

  void _update(
    int generation,
    VoiceMessageViewState Function(VoiceMessageViewState state) update,
  ) {
    if (!mounted || generation != _generation) return;
    setState(() => _viewState = update(_viewState));
  }

  void _setError(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = error.toString();
      _viewState = _viewState.copyWith(isPlaying: false, isBuffering: false);
    });
  }

  Future<void> _release() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    await player?.dispose();
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null) return;
    if (_viewState.isCompleted) await player.seek(Duration.zero);
    await player.playOrPause();
  }

  void _seek(double fraction) {
    final duration = _viewState.duration;
    if (duration == Duration.zero) return;
    final position = Duration(
      microseconds: (duration.inMicroseconds * fraction.clamp(0, 1)).round(),
    );
    unawaited(_player?.seek(position));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _VoiceMessageError(onRetry: _initialize);
    }
    return VoiceMessageControls(
      state: _viewState,
      samples: DiscordVoiceWaveform.decode(widget.waveform),
      onTogglePlayback: _togglePlayback,
      onSeekFraction: _seek,
    );
  }
}

class VoiceMessageControls extends StatelessWidget {
  const VoiceMessageControls({
    required this.state,
    required this.samples,
    required this.onTogglePlayback,
    required this.onSeekFraction,
    super.key,
  });

  final VoiceMessageViewState state;
  final List<double> samples;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeekFraction;

  @override
  Widget build(BuildContext context) {
    final durationMicros = state.duration.inMicroseconds;
    final progress = durationMicros == 0
        ? 0.0
        : (state.position.inMicroseconds / durationMicros).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('voice-message-player'),
      width: double.infinity,
      height: 64,
      constraints: const BoxConstraints(maxWidth: 336),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('voice-message-play'),
            onPressed: onTogglePlayback,
            tooltip: state.isPlaying
                ? 'Pause voice message'
                : 'Play voice message',
            icon: state.isBuffering
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: VoiceWaveformSurface(
              samples: samples,
              progress: progress,
              enabled: durationMicros > 0,
              onSeekFraction: onSeekFraction,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatVoiceDuration(
              state.position > Duration.zero ? state.position : state.duration,
            ),
            key: const ValueKey('voice-message-time'),
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String formatVoiceDuration(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class VoiceWaveformSurface extends StatelessWidget {
  const VoiceWaveformSurface({
    required this.samples,
    this.progress = 0,
    this.enabled = false,
    this.onSeekFraction,
    this.activeColor,
    this.inactiveColor,
    this.semanticsLabel = 'Voice message waveform',
    super.key,
  });

  final List<double> samples;
  final double progress;
  final bool enabled;
  final ValueChanged<double>? onSeekFraction;
  final Color? activeColor;
  final Color? inactiveColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset position) {
          if (!enabled || constraints.maxWidth <= 0) return;
          onSeekFraction?.call(position.dx / constraints.maxWidth);
        }

        return Semantics(
          label: semanticsLabel,
          value: '${(progress * 100).round()}%',
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              key: const ValueKey('voice-message-waveform'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => seek(details.localPosition),
              onHorizontalDragUpdate: (details) => seek(details.localPosition),
              child: CustomPaint(
                painter: _VoiceWaveformPainter(
                  samples: samples,
                  progress: progress,
                  active: activeColor ?? FlucordColors.brand,
                  inactive:
                      inactiveColor ??
                      context.surfaces.muted.withValues(alpha: 0.58),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.samples,
    required this.progress,
    required this.active,
    required this.inactive,
  });

  final List<double> samples;
  final double progress;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = (size.width / 4).floor().clamp(12, 96);
    final values = samples.isEmpty ? const [0.22, 0.38, 0.56, 0.32] : samples;
    final step = size.width / count;
    final playedX = size.width * progress.clamp(0, 1);
    for (var index = 0; index < count; index++) {
      final sourceIndex = (index * values.length / count).floor();
      final amplitude = values[sourceIndex.clamp(0, values.length - 1)];
      final barHeight = math.max(4.0, size.height * amplitude.clamp(0.08, 1));
      final x = step * index + step / 2;
      final paint = Paint()
        ..color = x <= playedX ? active : inactive
        ..strokeWidth = math.min(2.4, step * 0.58)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, (size.height - barHeight) / 2),
        Offset(x, (size.height + barHeight) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.inactive != inactive;
}

class _VoiceMessageError extends StatelessWidget {
  const _VoiceMessageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('voice-message-error'),
    width: double.infinity,
    height: 64,
    constraints: const BoxConstraints(maxWidth: 336),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      border: Border.all(color: context.surfaces.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Voice message unavailable',
            style: TextStyle(fontSize: 11),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
