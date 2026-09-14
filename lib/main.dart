import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/app_bootstrap.dart';
import 'src/app_log.dart';
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
  await runZonedGuarded(() => _start(arguments), (error, stackTrace) {
    AppLog.error('app', 'uncaught', error: error, stackTrace: stackTrace);
  });
}

Future<void> _start(List<String> arguments) async {
  const demoMode = bool.fromEnvironment('FLUCORD_DEMO_MODE');
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppLog.open(
    Directory('${(await getApplicationSupportDirectory()).path}/logs'),
  );
  AppLog.info('app', 'starting, log file: ${AppLog.path ?? 'console only'}');
  FlutterError.onError = (details) {
    AppLog.error(
      'app',
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLog.error('app', 'uncaught', error: error, stackTrace: stackTrace);
    return true;
  };
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
