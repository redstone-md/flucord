import 'dart:io';

import '../domain/voice_processing.dart';
import 'json_settings_file.dart';

/// The microphone processing switches, kept in a file beside the stream
/// quality: they describe the machine's microphone and CPU, not the account.
final class FileVoiceProcessingRepository implements VoiceProcessingRepository {
  FileVoiceProcessingRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'voice_processing.json';

  final JsonSettingsFile _file;

  @override
  Future<VoiceProcessingSettings> load() async =>
      VoiceProcessingSettings.fromJson(await _file.read());

  @override
  Future<void> save(VoiceProcessingSettings settings) =>
      _file.write(settings.toJson());
}
