import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/stream_quality.dart';

/// Stream quality, kept in a file beside the streamer mode switches.
///
/// Same reasoning as those: the settings blob has no group for them, and they
/// belong to whoever is sitting at the machine rather than to the account
/// signed in on it.
final class FileStreamQualityRepository implements StreamQualityRepository {
  FileStreamQualityRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'stream_quality.json';

  final Future<Directory> Function() _directory;

  @override
  Future<StreamQualitySettings> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const StreamQualitySettings();
      return StreamQualitySettings.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on Object {
      // Defaults rather than a failure to start: nothing here is worth
      // refusing to open the client over.
      return const StreamQualitySettings();
    }
  }

  @override
  Future<void> save(StreamQualitySettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');
}
