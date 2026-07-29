import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/keybind.dart';

/// Keybinds, kept in a file beside the client's other local state.
///
/// Not in the chat cache: that database is emptied when the account changes,
/// and a keybind belongs to whoever is sitting at the machine rather than to
/// the account they happen to be signed into. Not in the secure store either —
/// these are preferences, not secrets, and putting them there would ask the
/// keyring for something it has no business guarding.
final class FileKeybindRepository implements KeybindRepository {
  FileKeybindRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'keybinds.json';

  final Future<Directory> Function() _directory;

  @override
  Future<Map<KeybindAction, Keybind>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          ?KeybindAction.fromCode('${entry.key}'): ?Keybind.fromJson(
            entry.value,
          ),
      };
    } on Object {
      // A file that cannot be read or parsed leaves the client with no
      // bindings rather than no client: nothing here is worth failing to
      // start over.
      return {};
    }
  }

  @override
  Future<void> save(Map<KeybindAction, Keybind> bindings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        for (final entry in bindings.entries)
          entry.key.code: entry.value.toJson(),
      }),
    );
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');
}
