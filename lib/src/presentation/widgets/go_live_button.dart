import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/go_live_controller.dart';
import '../../domain/go_live_stream.dart';
import '../../theme/flucord_theme.dart';

/// Starts and ends a Go Live stream from inside the voice room.
class GoLiveButton extends StatelessWidget {
  const GoLiveButton({
    required this.controller,
    required this.channelId,
    this.guildId,
    super.key,
  });

  final GoLiveController controller;
  final String channelId;
  final String? guildId;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported) return const SizedBox.shrink();
    final streaming =
        controller.isStreaming ||
        controller.status == GoLiveStatus.creating ||
        controller.status == GoLiveStatus.connecting;
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
    // The primary display, which is what Discord's own share defaults to; the
    // picker for the rest is a separate surface. Which display that is comes
    // from the platform — the id cannot be guessed.
    await controller.start(channelId: channelId, guildId: guildId);
  }
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
