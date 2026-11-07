import 'dart:io';

import '../domain/client_sounds.dart';
import 'json_settings_file.dart';

/// The client sound switch, kept in a file beside the other machine
/// settings. Discord keeps its own sound switches on the machine too.
final class FileClientSoundSettingsRepository
    implements ClientSoundSettingsRepository {
  FileClientSoundSettingsRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile('client_sounds.json', directory: directory);

  final JsonSettingsFile _file;

  @override
  Future<bool> loadEnabled() async {
    final document = await _file.read();
    return switch (document) {
      {'enabled': final bool enabled} => enabled,
      _ => true,
    };
  }

  @override
  Future<void> saveEnabled({required bool enabled}) =>
      _file.write({'enabled': enabled});
}
