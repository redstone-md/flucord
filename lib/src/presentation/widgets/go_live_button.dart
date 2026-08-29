import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/go_live_controller.dart';
import '../../application/stream_quality_controller.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/stream_quality.dart';
import '../../theme/flucord_theme.dart';

/// Starts and ends a Go Live stream from inside the voice room.
class GoLiveButton extends StatelessWidget {
  const GoLiveButton({
    required this.controller,
    required this.channelId,
    this.guildId,
    this.pickSource,
    this.quality,
    super.key,
  });

  final GoLiveController controller;
  final String channelId;
  final String? guildId;

  /// Where the share's frame rate and size are picked, when the surface has
  /// the setting to offer. The menu next to the share button, the way
  /// Discord's own client places it; a running share follows the pick.
  final StreamQualityController? quality;

  /// Asks which screen or window to share, answering null when the picker was
  /// dismissed. Absent on a surface with no picker, where the primary screen
  /// is shared instead.
  final Future<String?> Function()? pickSource;

  @override
  Widget build(BuildContext context) {
    // Shown even where it cannot be used. This is the room's only share
    // control now, and a control that vanishes leaves somebody looking for a
    // button rather than reading why there isn't one.
    if (!controller.isSupported) {
      return IconButton(
        key: const ValueKey('go-live-toggle'),
        tooltip: 'Screen sharing needs a Discord session',
        onPressed: null,
        icon: const Icon(Icons.screen_share_outlined),
      );
    }
    final streaming = controller.isSharing;
    return Row(
      key: const ValueKey('go-live-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (streaming && controller.viewerIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              '${controller.viewerIds.length} watching',
              key: const ValueKey('go-live-viewers'),
              style: TextStyle(color: context.surfaces.muted, fontSize: 11),
            ),
          ),
        IconButton(
          key: const ValueKey('go-live-toggle'),
          tooltip: streaming ? 'Stop streaming' : 'Share your screen',
          // A build without the native encoder can still watch, so the control
          // says why rather than vanishing.
          onPressed: !controller.canEncode && !streaming
              ? null
              : () => unawaited(_toggle(context, streaming: streaming)),
          color: streaming ? FlucordColors.danger : null,
          icon: Icon(
            streaming ? Icons.stop_screen_share : Icons.screen_share_outlined,
          ),
        ),
        if (quality case final quality? when controller.canEncode)
          _QualityMenu(quality: quality),
        if (streaming)
          IconButton(
            key: const ValueKey('go-live-pause'),
            tooltip: controller.status == GoLiveStatus.paused
                ? 'Resume'
                : 'Pause',
            onPressed: () => unawaited(
              controller.setPaused(
                paused: controller.status != GoLiveStatus.paused,
              ),
            ),
            icon: Icon(
              controller.status == GoLiveStatus.paused
                  ? Icons.play_arrow
                  : Icons.pause,
            ),
          ),
        if (controller.error case final error?)
          Tooltip(
            // What Discord actually said, rather than the fixed sentence the
            // room used to show for every refusal. "Missing permissions" and
            // "no encoder on this machine" need different things done about
            // them, and only the answer says which happened.
            message:
                'Discord did not accept the stream: '
                '${_describe(error)}',
            child: Icon(
              Icons.error_outline,
              key: const ValueKey('go-live-error'),
              size: 15,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, {required bool streaming}) async {
    if (streaming) {
      await controller.stop();
      return;
    }
    final picker = pickSource;
    String? sourceId;
    if (picker != null) {
      sourceId = await picker();
      // Dismissed. Starting the primary screen because somebody closed a
      // picker would share the wrong thing, which is worse than sharing
      // nothing.
      if (sourceId == null) return;
    }
    await controller.start(
      channelId: channelId,
      guildId: guildId,
      sourceId: sourceId,
    );
  }
}

/// The frame rate and size picker: two lists of choices, one marked.
class _QualityMenu extends StatelessWidget {
  const _QualityMenu({required this.quality});

  final StreamQualityController quality;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.surfaces.muted, fontSize: 11);
    return PopupMenuButton<void>(
      key: const ValueKey('go-live-quality'),
      tooltip: 'Stream quality',
      icon: const Icon(Icons.expand_more, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          height: 28,
          child: Text('Frame rate', style: muted),
        ),
        for (final frameRate in StreamQualitySettings.frameRates)
          _choice(
            key: ValueKey('go-live-fps-$frameRate'),
            label: '$frameRate FPS',
            selected: quality.shareFrameRate == frameRate,
            onTap: () => unawaited(quality.setShareFrameRate(frameRate)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          enabled: false,
          height: 28,
          child: Text('Resolution', style: muted),
        ),
        for (final resolution in StreamResolution.values)
          _choice(
            key: ValueKey('go-live-res-${resolution.height}'),
            label: resolution.label,
            selected: quality.shareResolution == resolution,
            onTap: () => unawaited(quality.setShareResolution(resolution)),
          ),
      ],
    );
  }

  PopupMenuEntry<void> _choice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => PopupMenuItem<void>(
    key: key,
    height: 36,
    onTap: onTap,
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 16,
        ),
      ],
    ),
  );
}

/// One line of whatever went wrong.
///
/// Trimmed because these arrive as API exceptions with a payload attached,
/// and a tooltip is not the place for a paragraph.
String _describe(Object error) {
  final lines = const LineSplitter().convert(error.toString().trim());
  final firstLine = lines.isEmpty ? '' : lines.first.trim();
  const limit = 140;
  return firstLine.length <= limit
      ? firstLine
      : '${firstLine.substring(0, limit)}…';
}
