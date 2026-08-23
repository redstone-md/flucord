import 'package:flutter/widgets.dart';

import '../../domain/voice_message_recorder.dart';

/// Publishes the voice message recorder to the conversation pane's composer.
///
/// A plain service rather than a listenable, so this is an [InheritedWidget]:
/// nothing about the recorder changes what the pane draws until the composer
/// itself acts on it. Absent in hosts with no microphone to record with, and
/// the composer hides the record button.
final class VoiceMessageRecorderScope extends InheritedWidget {
  const VoiceMessageRecorderScope({
    required this.recorder,
    required super.child,
    super.key,
  });

  final VoiceMessageRecorder? recorder;

  @override
  bool updateShouldNotify(VoiceMessageRecorderScope oldWidget) =>
      oldWidget.recorder != recorder;

  static VoiceMessageRecorder? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VoiceMessageRecorderScope>()
          ?.recorder;
}
