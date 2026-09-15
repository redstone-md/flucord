import 'dart:io';

import '../domain/accessibility.dart';
import 'json_settings_file.dart';

/// The accessibility dials, kept in a file beside the keybinds.
///
/// Same reasoning as those: the settings blob has no group for them, and
/// they belong to whoever is sitting at the machine rather than to the
/// account signed in on it.
final class FileAccessibilityRepository implements AccessibilityRepository {
  FileAccessibilityRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'accessibility.json';

  final JsonSettingsFile _file;

  @override
  Future<AccessibilitySettings> load() async =>
      AccessibilitySettings.fromJson(await _file.read());

  @override
  Future<void> save(AccessibilitySettings settings) =>
      _file.write(settings.toJson());
}
