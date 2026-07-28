part of 'voice_controller.dart';

/// The device half of the controller: which microphone and speaker the session
/// uses, whether the microphone is live, and what is being shared.
///
/// Split out because none of it touches the connection state machine — it acts
/// on the media service and republishes — and keeping it beside the join and
/// leave paths made the file harder to follow than the two concerns are apart.
extension VoiceControllerDevices on VoiceController {
  Future<void> selectInput(String deviceId) async {
    if (_selectedInputId == deviceId) return;
    await _run(() async {
      _selectedInputId = deviceId;
      if (isConnected) {
        await _mediaService.startMicrophone(deviceId);
        await _mediaService.setMicrophoneEnabled(!_isMuted);
      }
    });
  }

  Future<void> selectOutput(String deviceId) async {
    if (_selectedOutputId == deviceId) return;
    await _run(() async {
      final playbackService = _playbackService;
      if (playbackService == null) {
        await _mediaService.selectAudioOutput(deviceId);
      } else {
        await playbackService.selectOutput(deviceId);
      }
      _selectedOutputId = deviceId;
    });
  }

  Future<void> toggleMute() async {
    if (!isConnected) return;
    await _run(() async {
      _isMuted = !_isMuted;
      await _mediaService.setMicrophoneEnabled(!_isMuted);
      await _audioPipeline?.setEnabled(!_isMuted && isTransportReady);
      await _sendJoin();
    });
  }

  Future<void> loadCaptureSources() async {
    await _run(() async {
      _captureSources = await _mediaService.enumerateCaptureSources();
    });
  }

  Future<void> shareScreen(String sourceId) async {
    await _run(() async {
      await _mediaService.startScreenShare(sourceId);
      _isScreenSharing = true;
    });
  }

  Future<void> stopScreenShare() async {
    await _run(() async {
      await _mediaService.stopScreenShare();
      _isScreenSharing = false;
    });
  }
}
