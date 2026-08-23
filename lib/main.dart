import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/app_bootstrap.dart';
import 'src/application/connection_controller.dart';
import 'src/data/native_opus_codec.dart';
import 'src/data/native_voice_message_recorder.dart';
import 'src/data/soloud_voice_playback_service.dart';
import 'src/data/webrtc_voice_media_service.dart';
import 'src/platform/desktop_integration.dart';
import 'src/platform/linux_desktop_integration.dart';
import 'src/platform/macos_desktop_integration.dart';
import 'src/platform/windows_desktop_integration.dart';

Future<void> main(List<String> arguments) async {
  const demoMode = bool.fromEnvironment('FLUCORD_DEMO_MODE');
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final DesktopIntegration? desktopIntegration = Platform.isWindows
      ? WindowsDesktopIntegration()
      : Platform.isMacOS
      ? MacosDesktopIntegration()
      : Platform.isLinux
      ? LinuxDesktopIntegration(initialArguments: arguments)
      : null;
  await desktopIntegration?.initialize();
  final opusCodecFactory = await NativeOpusCodecFactory.initialize();
  final bootstrap = demoMode
      ? AppBootstrap(
          initialSessionMode: SessionMode.demo,
          desktopIntegration: desktopIntegration,
          voiceMediaService: WebRtcVoiceMediaService(),
          voiceOpusCodecFactory: opusCodecFactory,
          voiceMessageRecorder: NativeVoiceMessageRecorder(opusCodecFactory),
          voicePlaybackService: SoLoudVoicePlaybackService(),
        )
      : AppBootstrap(
          desktopIntegration: desktopIntegration,
          voiceMediaService: WebRtcVoiceMediaService(),
          voiceOpusCodecFactory: opusCodecFactory,
          voiceMessageRecorder: NativeVoiceMessageRecorder(opusCodecFactory),
          voicePlaybackService: SoLoudVoicePlaybackService(),
        );
  runApp(FlucordApp(bootstrap: bootstrap));
}
