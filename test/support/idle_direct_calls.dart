import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';

/// A call controller on a session with no call plane: nothing ever rings.
/// Both controllers are torn down with the test.
DirectCallController idleDirectCalls() {
  final voice = VoiceController(const NoopVoiceMediaService());
  final calls = DirectCallController(
    serviceProvider: () => null,
    voiceController: voice,
  );
  addTearDown(voice.dispose);
  addTearDown(calls.dispose);
  return calls;
}
