import 'dart:io';

import '../domain/keybind.dart';
import 'json_settings_file.dart';

/// Keybinds, kept in a file beside the client's other local state.
///
/// Not in the chat cache: that database is emptied when the account changes,
/// and a keybind belongs to whoever is sitting at the machine rather than to
/// the account they happen to be signed into. Not in the secure store either —
/// these are preferences, not secrets, and putting them there would ask the
/// keyring for something it has no business guarding.
final class FileKeybindRepository implements KeybindRepository {
  FileKeybindRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'keybinds.json';

  final JsonSettingsFile _file;

  @override
  Future<Map<KeybindAction, Keybind>> load() async {
    final decoded = await _file.read();
    if (decoded is! Map) return {};
    try {
      return {
        for (final entry in decoded.entries)
          ?KeybindAction.fromCode('${entry.key}'): ?Keybind.fromJson(
            entry.value,
          ),
      };
    } on Object {
      // A file that cannot be parsed leaves the client with no bindings
      // rather than no client: nothing here is worth failing to start over.
      return {};
    }
  }

  @override
  Future<void> save(Map<KeybindAction, Keybind> bindings) => _file.write({
    for (final entry in bindings.entries) entry.key.code: entry.value.toJson(),
  });
}
