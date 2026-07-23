import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../theme/flucord_theme.dart';

typedef InlineVideoBuilder =
    Widget Function({
      required String url,
      required double aspectRatio,
      Key? key,
    });

Widget buildNativeInlineVideo({
  required String url,
  required double aspectRatio,
  Key? key,
}) => NativeInlineVideoPlayer(key: key, url: url, aspectRatio: aspectRatio);

final class InlineVideoViewState {
  const InlineVideoViewState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = true,
    this.isMuted = false,
    this.isCompleted = false,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool isMuted;
  final bool isCompleted;

  InlineVideoViewState copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? isMuted,
    bool? isCompleted,
  }) => InlineVideoViewState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    isMuted: isMuted ?? this.isMuted,
    isCompleted: isCompleted ?? this.isCompleted,
  );
}

class NativeInlineVideoPlayer extends StatefulWidget {
  const NativeInlineVideoPlayer({
    required this.url,
    required this.aspectRatio,
    super.key,
  });

  final String url;
  final double aspectRatio;

  @override
  State<NativeInlineVideoPlayer> createState() =>
      _NativeInlineVideoPlayerState();
}

class _NativeInlineVideoPlayerState extends State<NativeInlineVideoPlayer> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Player? _player;
  VideoController? _videoController;
  InlineVideoViewState _viewState = const InlineVideoViewState();
  String? _error;
  double _audibleVolume = 100;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant NativeInlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _initialize();
  }

  @override
  void dispose() {
    _generation++;
    _release();
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    await _release();
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = null;
      _viewState = const InlineVideoViewState();
    });
    try {
      final player = Player();
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: 960,
          height: 540,
        ),
      );
      _player = player;
      _videoController = controller;
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
      player.stream.duration.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(duration: value)),
      ),
      player.stream.buffering.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(isBuffering: value)),
      ),
      player.stream.volume.listen((value) {
        if (value > 0) _audibleVolume = value;
        _update(generation, (state) => state.copyWith(isMuted: value <= 0));
      }),
      player.stream.completed.listen(
        (value) =>
            _update(generation, (state) => state.copyWith(isCompleted: value)),
      ),
      player.stream.error.listen((value) => _setError(value, generation)),
    ]);
  }

  void _update(
    int generation,
    InlineVideoViewState Function(InlineVideoViewState state) update,
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
    _videoController = null;
    await player?.dispose();
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null) return;
    if (_viewState.isCompleted) await player.seek(Duration.zero);
    await player.playOrPause();
  }

  Future<void> _toggleMute() async {
    final player = _player;
    if (player == null) return;
    await player.setVolume(_viewState.isMuted ? _audibleVolume : 0);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 300),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio.clamp(0.65, 2.2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null)
                  Video(
                    key: _videoKey,
                    controller: controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    fill: Colors.black,
                  ),
                if (_error != null)
                  _InlineVideoError(onRetry: _initialize)
                else ...[
                  if (_viewState.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: InlineVideoControls(
                      state: _viewState,
                      onTogglePlayback: _togglePlayback,
                      onToggleMute: _toggleMute,
                      onSeek: (position) => _player?.seek(position),
                      onFullscreen: () =>
                          _videoKey.currentState?.toggleFullscreen(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InlineVideoControls extends StatelessWidget {
  const InlineVideoControls({
    required this.state,
    required this.onTogglePlayback,
    required this.onToggleMute,
    required this.onSeek,
    required this.onFullscreen,
    super.key,
  });

  final InlineVideoViewState state;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleMute;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final durationMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds.clamp(0, durationMs);
    return Container(
      key: const ValueKey('inline-video-controls'),
      height: 44,
      color: Colors.black.withValues(alpha: 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _controlButton(
            icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
            tooltip: state.isPlaying ? 'Pause' : 'Play',
            onPressed: onTogglePlayback,
          ),
          _controlButton(
            icon: state.isMuted ? Icons.volume_off : Icons.volume_up,
            tooltip: state.isMuted ? 'Unmute' : 'Mute',
            onPressed: onToggleMute,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: FlucordColors.brand,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: FlucordColors.brand.withValues(alpha: 0.18),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                key: const ValueKey('inline-video-seek'),
                value: durationMs == 0 ? 0 : positionMs.toDouble(),
                max: durationMs == 0 ? 1 : durationMs.toDouble(),
                onChanged: durationMs == 0
                    ? null
                    : (value) => onSeek(Duration(milliseconds: value.round())),
              ),
            ),
          ),
          Text(
            '${_formatDuration(state.position)} / '
            '${_formatDuration(state.duration)}',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          _controlButton(
            icon: Icons.fullscreen,
            tooltip: 'Fullscreen',
            onPressed: onFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, size: 18, color: Colors.white),
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
  );

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _InlineVideoError extends StatelessWidget {
  const _InlineVideoError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.surfaces.inset,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_file_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          const Text('Video unavailable', style: TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
