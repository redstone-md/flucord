part of 'message_composer.dart';

mixin _VoiceMessageComposerStateMixin on State<MessageComposer> {
  StreamSubscription<VoiceMessageRecordingProgress>? _voiceProgressSubscription;

  /// Fed per frame without a rebuild: only the waveform and clock listen.
  final VoiceRecordingLevels _voiceLevels = VoiceRecordingLevels();
  bool _isRecordingVoice = false;

  /// Between the stop and the recorder's answer, while the capture hands
  /// over its last frames and the file is written.
  bool _isStoppingVoice = false;
  int _voiceGeneration = 0;

  bool get _hasRegularMessageContent;
  bool get _isHeldBySlowmode;
  bool get _hasVoiceSession => _isRecordingVoice || _isStoppingVoice;
  bool get _canRecordVoice =>
      widget.voiceMessageRecorder != null &&
      widget.onSendVoiceMessage != null &&
      !_hasRegularMessageContent &&
      !_isHeldBySlowmode &&
      widget.replyTo == null &&
      !widget.isSending;

  void _listenToVoiceProgress() {
    _voiceProgressSubscription = widget.voiceMessageRecorder?.progress.listen(
      (progress) {
        if (mounted && (_isRecordingVoice || _isStoppingVoice)) {
          _voiceLevels.add(progress);
        }
      },
      onError: (Object error) {
        if (mounted) unawaited(_abortVoiceCapture(error));
      },
    );
  }

  Future<void> _startVoiceRecording() async {
    if (!_canRecordVoice || _hasVoiceSession) return;
    final recorder = widget.voiceMessageRecorder!;
    final generation = ++_voiceGeneration;
    _voiceLevels.clear();
    setState(() => _isRecordingVoice = true);
    try {
      await recorder.start();
      if (generation != _voiceGeneration && recorder.isRecording) {
        await recorder.cancel();
      }
    } catch (error) {
      if (!mounted || generation != _voiceGeneration) return;
      setState(() => _isRecordingVoice = false);
      _showVoiceFailure('The microphone could not be started.');
    }
  }

  /// Stops the recording and hands it over to be sent. The message shows in
  /// the timeline from here, so the composer is free again at once.
  Future<void> _stopAndSendVoiceMessage() async {
    if (!_isRecordingVoice) return;
    final recorder = widget.voiceMessageRecorder!;
    final send = widget.onSendVoiceMessage!;
    final generation = _voiceGeneration;
    setState(() {
      _isRecordingVoice = false;
      _isStoppingVoice = true;
    });
    try {
      final pending = await recorder.stop();
      if (!mounted || generation != _voiceGeneration) {
        await _deleteVoiceMessageIgnoringErrors(recorder, pending);
        return;
      }
      send(
        pending,
        () => unawaited(_deleteVoiceMessageIgnoringErrors(recorder, pending)),
      );
    } catch (_) {
      if (!mounted || generation != _voiceGeneration) return;
      _showVoiceFailure('The voice recording could not be prepared.');
    } finally {
      // A newer generation already reset this state.
      if (mounted && generation == _voiceGeneration) {
        _voiceLevels.clear();
        setState(() => _isStoppingVoice = false);
      }
    }
  }

  Future<void> _cancelVoiceMessage() async {
    final recorder = widget.voiceMessageRecorder;
    _voiceGeneration++;
    _voiceLevels.clear();
    setState(() => _isRecordingVoice = false);
    if (recorder?.isRecording ?? false) {
      await _cancelVoiceRecordingIgnoringErrors(recorder);
    }
  }

  Future<void> _abortVoiceCapture(Object error) async {
    if (!mounted || !_isRecordingVoice) return;
    await _cancelVoiceMessage();
    if (!mounted) return;
    _showVoiceFailure('Recording stopped because the microphone failed.');
  }

  /// Drops a recording in progress. One that is stopping is deleted by the
  /// stop, once the recorder hands it back.
  void _discardVoiceState(VoiceMessageRecorder? recorder) {
    final wasStopping = _isStoppingVoice;
    _voiceGeneration++;
    _isRecordingVoice = false;
    _isStoppingVoice = false;
    _voiceLevels.clear();
    if ((recorder?.isRecording ?? false) && !wasStopping) {
      unawaited(_cancelVoiceRecordingIgnoringErrors(recorder));
    }
  }

  Future<void> _cancelVoiceRecordingIgnoringErrors(
    VoiceMessageRecorder? recorder,
  ) async {
    try {
      await recorder?.cancel();
    } on Object {
      // The local session is already detached from the composer.
    }
  }

  Future<void> _deleteVoiceMessageIgnoringErrors(
    VoiceMessageRecorder? recorder,
    PendingVoiceMessage pending,
  ) async {
    try {
      await recorder?.delete(pending);
    } on Object {
      // The recorder retains ownership and retries cleanup during disposal.
    }
  }

  void _showVoiceFailure(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _VoiceMessageComposerBar extends StatelessWidget {
  const _VoiceMessageComposerBar({
    required this.levels,
    required this.isRecording,
    required this.onCancel,
    required this.onSend,
  });

  final VoiceRecordingLevels levels;

  /// False while the recording stops and its file is written.
  final bool isRecording;
  final VoidCallback? onCancel;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      key: const ValueKey('voice-message-composer'),
      height: 48,
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: FlucordRadius.small,
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('cancel-voice-message'),
            onPressed: onCancel,
            tooltip: 'Cancel voice recording',
            icon: const FlucordIcon(FlucordIcons.delete, size: 20),
          ),
          if (isRecording) ...[
            Container(
              key: const ValueKey('voice-recording-indicator'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: errorColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: isRecording
                ? VoiceRecordingWaveform(
                    key: const ValueKey('voice-recording-waveform'),
                    levels: levels,
                    color: errorColor,
                  )
                : VoiceWaveformSurface(
                    key: const ValueKey('voice-recording-waveform'),
                    samples: levels.levels,
                    activeColor: context.surfaces.brand,
                    semanticsLabel: 'Recorded voice message waveform',
                  ),
          ),
          const SizedBox(width: 8),
          VoiceRecordingClock(
            key: const ValueKey('voice-recording-time'),
            levels: levels,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 4),
          if (isRecording)
            IconButton(
              key: const ValueKey('send-voice-message'),
              onPressed: onSend,
              tooltip: 'Stop and send voice message',
              icon: FlucordIcon(
                FlucordIcons.send,
                size: 20,
                color: context.surfaces.accentIcon,
              ),
            )
          else
            const SizedBox.square(
              key: ValueKey('voice-message-stopping'),
              dimension: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
