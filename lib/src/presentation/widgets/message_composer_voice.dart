part of 'message_composer.dart';

mixin _VoiceMessageComposerStateMixin on State<MessageComposer> {
  StreamSubscription<VoiceMessageRecordingProgress>? _voiceProgressSubscription;
  VoiceMessageRecordingProgress _voiceProgress = VoiceMessageRecordingProgress(
    duration: Duration.zero,
    samples: const [],
  );
  PendingVoiceMessage? _pendingVoiceMessage;
  Object? _voiceError;
  bool _isRecordingVoice = false;
  bool _isUploadingVoice = false;
  int _voiceGeneration = 0;

  bool get _hasRegularMessageContent;
  bool get _hasVoiceSession =>
      _isRecordingVoice || _pendingVoiceMessage != null || _isUploadingVoice;
  bool get _canRecordVoice =>
      widget.voiceMessageRecorder != null &&
      widget.onSendVoiceMessage != null &&
      !_hasRegularMessageContent &&
      widget.replyTo == null &&
      !widget.isSending;

  void _listenToVoiceProgress() {
    _voiceProgressSubscription = widget.voiceMessageRecorder?.progress.listen(
      (progress) {
        if (!mounted || !_isRecordingVoice) return;
        setState(() => _voiceProgress = progress);
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
    setState(() {
      _isRecordingVoice = true;
      _voiceError = null;
      _voiceProgress = VoiceMessageRecordingProgress(
        duration: Duration.zero,
        samples: const [],
      );
    });
    try {
      await recorder.start();
      if (generation != _voiceGeneration && recorder.isRecording) {
        await recorder.cancel();
      }
    } catch (error) {
      if (!mounted || generation != _voiceGeneration) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceError = error;
      });
      _showVoiceFailure('The microphone could not be started.');
    }
  }

  Future<void> _stopAndSendVoiceMessage() async {
    if (!_isRecordingVoice || _isUploadingVoice) return;
    final recorder = widget.voiceMessageRecorder!;
    final send = widget.onSendVoiceMessage!;
    final generation = _voiceGeneration;
    setState(() {
      _isRecordingVoice = false;
      _isUploadingVoice = true;
      _voiceError = null;
    });
    try {
      final pending = await recorder.stop();
      if (!mounted || generation != _voiceGeneration) {
        await _deleteVoiceMessageIgnoringErrors(recorder, pending);
        return;
      }
      setState(() => _pendingVoiceMessage = pending);
      await _uploadVoiceMessage(pending, send, generation);
    } catch (error) {
      if (!mounted || generation != _voiceGeneration) return;
      setState(() {
        _isUploadingVoice = false;
        _voiceError = error;
      });
      _showVoiceFailure('The voice recording could not be prepared.');
    }
  }

  Future<void> _retryVoiceMessage() async {
    final pending = _pendingVoiceMessage;
    final send = widget.onSendVoiceMessage;
    if (pending == null || send == null || _isUploadingVoice) return;
    await _uploadVoiceMessage(pending, send, _voiceGeneration);
  }

  Future<void> _uploadVoiceMessage(
    PendingVoiceMessage pending,
    SendVoiceMessageCallback send,
    int generation,
  ) async {
    setState(() {
      _isUploadingVoice = true;
      _voiceError = null;
    });
    Object? failure;
    var sent = false;
    try {
      sent = await send(pending);
    } catch (error) {
      failure = error;
    }
    if (!mounted || generation != _voiceGeneration) {
      await _deleteVoiceMessageIgnoringErrors(
        widget.voiceMessageRecorder,
        pending,
      );
      return;
    }
    if (sent) {
      await _deleteVoiceMessageIgnoringErrors(
        widget.voiceMessageRecorder,
        pending,
      );
      if (!mounted || generation != _voiceGeneration) return;
      setState(() {
        _pendingVoiceMessage = null;
        _isUploadingVoice = false;
        _voiceError = null;
        _voiceProgress = VoiceMessageRecordingProgress(
          duration: Duration.zero,
          samples: const [],
        );
      });
      return;
    }
    setState(() {
      _isUploadingVoice = false;
      _voiceError = failure ?? StateError('Voice message upload failed');
    });
  }

  Future<void> _cancelVoiceMessage() async {
    final recorder = widget.voiceMessageRecorder;
    final pending = _pendingVoiceMessage;
    _voiceGeneration++;
    setState(() {
      _isRecordingVoice = false;
      _isUploadingVoice = false;
      _pendingVoiceMessage = null;
      _voiceError = null;
      _voiceProgress = VoiceMessageRecordingProgress(
        duration: Duration.zero,
        samples: const [],
      );
    });
    if (recorder?.isRecording ?? false) {
      await _cancelVoiceRecordingIgnoringErrors(recorder);
    }
    if (pending != null) {
      await _deleteVoiceMessageIgnoringErrors(recorder, pending);
    }
  }

  Future<void> _abortVoiceCapture(Object error) async {
    if (!mounted || !_isRecordingVoice) return;
    await _cancelVoiceMessage();
    if (!mounted) return;
    _voiceError = error;
    _showVoiceFailure('Recording stopped because the microphone failed.');
  }

  void _discardVoiceState(VoiceMessageRecorder? recorder) {
    final pending = _pendingVoiceMessage;
    final wasUploading = _isUploadingVoice;
    _voiceGeneration++;
    _isRecordingVoice = false;
    _isUploadingVoice = false;
    _pendingVoiceMessage = null;
    _voiceError = null;
    _voiceProgress = VoiceMessageRecordingProgress(
      duration: Duration.zero,
      samples: const [],
    );
    if ((recorder?.isRecording ?? false) && !wasUploading) {
      unawaited(_cancelVoiceRecordingIgnoringErrors(recorder));
    }
    if (pending != null && !wasUploading) {
      unawaited(_deleteVoiceMessageIgnoringErrors(recorder, pending));
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
    required this.progress,
    required this.isRecording,
    required this.isUploading,
    required this.hasPendingMessage,
    required this.error,
    required this.onCancel,
    required this.onPrimaryAction,
  });

  final VoiceMessageRecordingProgress progress;
  final bool isRecording;
  final bool isUploading;
  final bool hasPendingMessage;
  final Object? error;
  final VoidCallback? onCancel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      key: const ValueKey('voice-message-composer'),
      height: 48,
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('cancel-voice-message'),
            onPressed: onCancel,
            tooltip: isRecording
                ? 'Cancel voice recording'
                : 'Discard voice message',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
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
            child: VoiceWaveformSurface(
              key: const ValueKey('voice-recording-waveform'),
              samples: progress.samples,
              progress: isRecording ? 1 : 0,
              activeColor: isRecording ? errorColor : FlucordColors.brand,
              semanticsLabel: isRecording
                  ? 'Live voice recording waveform'
                  : 'Recorded voice message waveform',
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatVoiceDuration(progress.duration),
            key: const ValueKey('voice-recording-time'),
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (error != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: hasPendingMessage
                  ? 'Voice message could not be sent'
                  : 'Voice recording failed',
              child: Icon(Icons.error_outline, size: 17, color: errorColor),
            ),
          ],
          const SizedBox(width: 4),
          if (isUploading)
            const SizedBox.square(
              key: ValueKey('voice-message-uploading'),
              dimension: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              key: ValueKey(
                isRecording ? 'send-voice-message' : 'retry-voice-message',
              ),
              onPressed: onPrimaryAction,
              tooltip: isRecording
                  ? 'Stop and send voice message'
                  : 'Retry voice message',
              icon: Icon(
                isRecording ? Icons.send_rounded : Icons.refresh_rounded,
                size: 20,
                color: FlucordColors.brand,
              ),
            ),
        ],
      ),
    );
  }
}
