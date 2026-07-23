import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/platform/desktop_integration.dart';
import 'src/platform/windows_desktop_integration.dart';
import 'src/data/webrtc_voice_media_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DesktopIntegration? desktopIntegration = Platform.isWindows
      ? WindowsDesktopIntegration()
      : null;
  await desktopIntegration?.initialize();
  runApp(
    FlucordApp(
      desktopIntegration: desktopIntegration,
      voiceMediaService: WebRtcVoiceMediaService(),
    ),
  );
}
