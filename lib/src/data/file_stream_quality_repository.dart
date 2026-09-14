import 'dart:io';

import '../domain/stream_quality.dart';
import 'json_settings_file.dart';

/// Stream quality, kept in a file beside the streamer mode switches.
///
/// Same reasoning as those: the settings blob has no group for them, and they
/// belong to whoever is sitting at the machine rather than to the account
/// signed in on it.
final class FileStreamQualityRepository implements StreamQualityRepository {
  FileStreamQualityRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'stream_quality.json';

  final JsonSettingsFile _file;

  @override
  Future<StreamQualitySettings> load() async =>
      StreamQualitySettings.fromJson(await _file.read());

  @override
  Future<void> save(StreamQualitySettings settings) =>
      _file.write(settings.toJson());
}
