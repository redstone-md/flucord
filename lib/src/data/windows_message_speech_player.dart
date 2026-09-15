import 'dart:convert';
import 'dart:io';

import '../domain/message_speech.dart';
import '../domain/soundboard_playback.dart';

/// Speaks a message's text through the machine's own speech synthesiser.
///
/// The synthesis is the operating system's, the same engine Discord's desktop
/// client leans on, and the result is a plain audio file: the playback rides
/// the same media playback layer the soundboard and the call sounds use, so
/// there is no second audio path in the client. A build without the
/// synthesiser says so through [MessageSpeechPlayer.isSupported] and a
/// spoken-aloud message arrives as an ordinary one.
final class WindowsMessageSpeechPlayer implements MessageSpeechPlayer {
  WindowsMessageSpeechPlayer({
    required SoundboardAudioPlayer player,
    Future<Directory> Function()? temporaryDirectory,
    DateTime Function()? now,
  }) : _player = player,
       _temporaryDirectory = temporaryDirectory ?? _systemTemp,
       _now = now ?? DateTime.now;

  /// Where the synthesised audio lands. Held as the function rather than the
  /// directory so a test does not write onto the machine running it.
  final Future<Directory> Function() _temporaryDirectory;
  final DateTime Function() _now;

  /// The media playback layer the synthesised audio plays through.
  final SoundboardAudioPlayer _player;

  /// The file the last message is being spoken from, so it can be removed
  /// once nothing reads it any more.
  File? _spoken;

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<bool> speak(String text) async {
    if (!isSupported || text.trim().isEmpty) return false;
    try {
      final directory = await _temporaryDirectory();
      final audio = File(
        '${directory.path}${Platform.pathSeparator}'
        'flucord-tts-${_now().microsecondsSinceEpoch.toRadixString(16)}.wav',
      );
      // The text travels on the command line, so it is encoded rather than
      // quoted: a message full of quotes must not be able to make the
      // synthesiser read something else.
      final encoded = base64Encode(utf8.encode(text));
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$text = [Text.Encoding]::UTF8.GetString('
            '[Convert]::FromBase64String(\'$encoded\')); '
            'Add-Type -AssemblyName System.Speech; '
            '\$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
            '\$voice.SetOutputToWaveFile(\'${audio.path}\'); '
            '\$voice.Speak(\$text); '
            '\$voice.Dispose()',
      ]);
      if (result.exitCode != 0 || !await audio.exists()) return false;
      final previous = _spoken;
      _spoken = audio;
      await _player.play(audio.path);
      // Only now is the previous file's handle gone: opening the new media is
      // what releases it. The delete is still best effort, and a file the
      // player happened to keep waits for the next message.
      await _delete(previous);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final file = _spoken;
    _spoken = null;
    await _delete(file);
  }

  static Future<Directory> _systemTemp() async => Directory.systemTemp;

  /// Drops a synthesised file, which nothing needs once it has played.
  Future<void> _delete(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // A temporary file that could not be removed is not worth a report.
    }
  }
}
