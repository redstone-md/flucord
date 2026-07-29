import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../application/voice_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/voice_media.dart';
import '../../theme/flucord_theme.dart';
import '../../domain/video_decoder.dart';
import 'voice_capture_source_dialog.dart';
import 'voice_participant_grid.dart';
import 'voice_room_status.dart';

class VoiceRoomView extends StatefulWidget {
  const VoiceRoomView({
    required this.guildId,
    required this.channelId,
    required this.channelName,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    this.stageControls,
    this.soundboard,
    this.goLive,
    this.streamViewer,
    this.cameraFrameFor,
    this._spaceId,
    super.key,
  });

  /// Null for a call in a DM or group DM, which has no guild. The room is
  /// otherwise identical — same grid, same devices, same toolbar — so the two
  /// share this widget instead of a second copy that could drift.
  final String? guildId;
  final String channelId;
  final String channelName;
  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;

  /// The latest picture from a participant's camera, when one is
  /// arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  /// The stage strip, or null for an ordinary voice channel.
  final Widget? stageControls;

  /// The soundboard button, or null where there is nothing to play into.
  final Widget? soundboard;

  /// The Go Live control, or null outside a server voice channel.
  final Widget? goLive;

  /// Somebody else's stream, drawn in place of the participant grid while it
  /// is being watched.
  final Widget? streamViewer;

  /// Which space's per-guild avatars to render. Defaults to [guildId] because
  /// for guild voice they are the same thing; a DM call has to supply the DM
  /// pseudo-space itself.
  final String? _spaceId;

  String get spaceId => _spaceId ?? guildId ?? '';

  @override
  State<VoiceRoomView> createState() => _VoiceRoomViewState();
}

class _VoiceRoomViewState extends State<VoiceRoomView> {
  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void didUpdateWidget(covariant VoiceRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guildId != widget.guildId ||
        oldWidget.channelId != widget.channelId) {
      unawaited(_connect());
    }
  }

  Future<void> _connect() {
    final guildId = widget.guildId;
    return guildId == null
        ? widget.controller.connectToCall(channelId: widget.channelId)
        : widget.controller.connect(
            guildId: guildId,
            channelId: widget.channelId,
          );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 720;
          final stage = Expanded(
            child: _VoiceStage(
              streamViewer: widget.streamViewer,
              goLive: widget.goLive,
              soundboard: widget.soundboard,
              stageControls: widget.stageControls,
              channelName: widget.channelName,
              controller: widget.controller,
              members: widget.members,
              currentMemberId: widget.currentMemberId,
              spaceId: widget.spaceId,
              cameraFrameFor: widget.cameraFrameFor,
            ),
          );
          return Column(
            children: [
              Expanded(
                child: horizontal
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          stage,
                          SizedBox(
                            width: 276,
                            child: _DevicePanel(
                              controller: widget.controller,
                              border: const Border(left: BorderSide()),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          stage,
                          SizedBox(
                            height: 170,
                            child: _DevicePanel(
                              controller: widget.controller,
                              border: const Border(top: BorderSide()),
                            ),
                          ),
                        ],
                      ),
              ),
              _VoiceToolbar(controller: widget.controller),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceStage extends StatelessWidget {
  const _VoiceStage({
    required this.streamViewer,
    required this.goLive,
    required this.soundboard,
    required this.stageControls,
    required this.channelName,
    required this.controller,
    required this.members,
    required this.currentMemberId,
    required this.spaceId,
    this.cameraFrameFor,
  });

  /// The latest picture from a participant's camera, when one is
  /// arriving.
  final DecodedVideoFrame? Function(String userId)? cameraFrameFor;

  final String channelName;
  final VoiceController controller;
  final List<Member> members;
  final String currentMemberId;
  final String spaceId;
  final Widget? stageControls;
  final Widget? soundboard;
  final Widget? goLive;
  final Widget? streamViewer;

  @override
  Widget build(BuildContext context) {
    if (controller.state == VoiceState.loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final renderer = controller.previewRenderer;
    if (controller.isScreenSharing && renderer is RTCVideoRenderer) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _StatusLabel(
                icon: Icons.screen_share_outlined,
                label: channelName,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?goLive,
              ?soundboard,
              const SizedBox(width: 12),
              Text(
                voiceRoomStatusLabel(controller),
                style: TextStyle(
                  color: controller.isTransportReady
                      ? FlucordColors.success
                      : context.surfaces.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // What is wrong, rather than the old fixed sentence: a room that says
        // nothing is indistinguishable from one that is simply quiet.
        if (voiceRoomWarning(controller) case final warning?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              warning,
              key: const ValueKey('voice-room-warning'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ),
        ?stageControls,
        Expanded(
          child:
              streamViewer ??
              VoiceParticipantGrid(
                participants: controller.participants,
                members: members,
                currentMemberId: currentMemberId,
                spaceId: spaceId,
                cameraFrameFor: cameraFrameFor,
              ),
        ),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.surfaces.raised.withValues(alpha: 0.92),
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({required this.controller, required this.border});

  final VoiceController controller;
  final Border border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(
          left: border.left.copyWith(color: context.surfaces.border),
          top: border.top.copyWith(color: context.surfaces.border),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'VOICE DEVICES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _DeviceSelect(
              label: 'Input device',
              devices: controller.inputDevices,
              selectedId: controller.selectedInputId,
              onChanged: controller.selectInput,
            ),
            const SizedBox(height: 12),
            _DeviceSelect(
              label: 'Output device',
              devices: controller.outputDevices,
              selectedId: controller.selectedOutputId,
              onChanged: controller.selectOutput,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSelect extends StatelessWidget {
  const _DeviceSelect({
    required this.label,
    required this.devices,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<VoiceDevice> devices;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: devices.any((device) => device.id == selectedId)
          ? selectedId
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      hint: const Text('System default'),
      items: [
        for (final device in devices)
          DropdownMenuItem(
            value: device.id,
            child: Text(device.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _VoiceToolbar extends StatelessWidget {
  const _VoiceToolbar({required this.controller});

  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('voice-mute'),
            onPressed: controller.isConnected && !controller.isBusy
                ? controller.toggleMute
                : null,
            tooltip: controller.isMuted ? 'Unmute' : 'Mute',
            style: _controlStyle(
              context,
              foreground: controller.isMuted ? FlucordColors.danger : null,
            ),
            icon: Icon(controller.isMuted ? Icons.mic_off : Icons.mic),
          ),
          const SizedBox(width: 12),
          IconButton(
            key: const ValueKey('voice-share-screen'),
            onPressed: controller.isConnected && !controller.isBusy
                ? () => _toggleScreenShare(context)
                : null,
            tooltip: controller.isScreenSharing
                ? 'Stop sharing'
                : 'Share screen',
            style: _controlStyle(
              context,
              foreground: controller.isScreenSharing
                  ? FlucordColors.brand
                  : null,
            ),
            icon: Icon(
              controller.isScreenSharing
                  ? Icons.stop_screen_share_outlined
                  : Icons.screen_share_outlined,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            key: const ValueKey('voice-disconnect'),
            onPressed: controller.isConnected && !controller.isBusy
                ? controller.disconnect
                : null,
            tooltip: 'Disconnect',
            style: IconButton.styleFrom(
              backgroundColor: FlucordColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.call_end),
          ),
        ],
      ),
    );
  }

  ButtonStyle _controlStyle(BuildContext context, {Color? foreground}) =>
      IconButton.styleFrom(
        backgroundColor: context.surfaces.raised,
        foregroundColor: foreground ?? Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: context.surfaces.border),
      );

  Future<void> _toggleScreenShare(BuildContext context) async {
    if (controller.isScreenSharing) {
      await controller.stopScreenShare();
      return;
    }
    await controller.loadCaptureSources();
    if (!context.mounted) return;
    final source = await showDialog<VoiceCaptureSource>(
      context: context,
      builder: (_) =>
          VoiceCaptureSourceDialog(sources: controller.captureSources),
    );
    if (source != null) await controller.shareScreen(source.id);
  }
}
