import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One JSON document in the application support directory.
///
/// Every machine-local setting (keybinds, streamer mode, stream quality, the
/// microphone filter) is one of these: they belong to whoever is sitting at
/// the machine rather than to the account signed in on it, and Discord's
/// settings blob has no group for them.
final class JsonSettingsFile {
  JsonSettingsFile(this.fileName, {Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final String fileName;
  final Future<Directory> Function() _directory;

  /// The decoded document, or null when there is none or it will not parse.
  ///
  /// Null rather than a failure to start: nothing kept in one of these is
  /// worth refusing to open the client over, and every reader has a default.
  Future<Object?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> write(Object? document) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(document));
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');
}
