import 'dart:io';

import '../domain/streamer_mode.dart';
import 'json_settings_file.dart';

/// Streamer mode's switches, kept in a file beside the keybinds.
///
/// Same reasoning as those: the settings blob has no group for them, and they
/// belong to whoever is sitting at the machine rather than to the account
/// signed in on it.
final class FileStreamerModeRepository implements StreamerModeRepository {
  FileStreamerModeRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'streamer_mode.json';

  final JsonSettingsFile _file;

  @override
  Future<StreamerModeSettings> load() async =>
      StreamerModeSettings.fromJson(await _file.read());

  @override
  Future<void> save(StreamerModeSettings settings) =>
      _file.write(settings.toJson());
}
