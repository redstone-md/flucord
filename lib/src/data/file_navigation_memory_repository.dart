import 'dart:io';

import '../domain/navigation_memory.dart';
import 'json_settings_file.dart';

/// The navigation memory, kept in a file beside the other local settings.
///
/// The file holds one account, as the chat cache does. Signing out empties it.
final class FileNavigationMemoryRepository
    implements NavigationMemoryRepository {
  FileNavigationMemoryRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'navigation_memory.json';

  final JsonSettingsFile _file;

  @override
  Future<NavigationMemory?> load() async =>
      NavigationMemory.fromJson(await _file.read());

  @override
  Future<void> save(NavigationMemory memory) => _file.write(memory.toJson());

  @override
  Future<void> clear() => _file.write(null);
}
