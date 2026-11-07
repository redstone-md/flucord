import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app_log.dart';
import '../domain/client_sounds.dart';
import 'discord/discord_sound_assets.dart';

/// Reads the bytes behind one address.
abstract interface class SoundFetcher {
  /// Throws when the address does not answer with a file.
  Future<List<int>> fetch(Uri uri);
}

/// Fetches over HTTPS with the platform client.
final class HttpSoundFetcher implements SoundFetcher {
  const HttpSoundFetcher();

  static const _timeout = Duration(seconds: 30);

  @override
  Future<List<int>> fetch(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('status ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await response.timeout(_timeout).forEach(bytes.addAll);
      return bytes;
    } finally {
      client.close();
    }
  }
}

/// Discord's sound files, fetched from Discord's asset host and kept in the
/// app's cache directory.
///
/// A file is named after its hashed name on the host, so a refreshed pin in
/// [discordSoundFiles] fetches the new file instead of reusing the old one.
final class DiscordSoundLibrary implements ClientSoundLibrary {
  DiscordSoundLibrary({
    SoundFetcher fetcher = const HttpSoundFetcher(),
    Future<Directory> Function()? directory,
  }) : _fetcher = fetcher,
       _directory = directory ?? _defaultDirectory;

  final SoundFetcher _fetcher;
  final Future<Directory> Function() _directory;
  final Map<ClientSound, Future<void>> _inFlight = {};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/sounds');

  @override
  Future<String?> localUrl(ClientSound sound) async {
    final file = await _fileFor(sound);
    if (file == null) return null;
    if (file.existsSync()) return file.uri.toString();
    unawaited(_fetch(sound));
    return null;
  }

  @override
  Future<void> fetchAll() => Future.wait(ClientSound.values.map(_fetch));

  Future<void> _fetch(ClientSound sound) => _inFlight.putIfAbsent(
    sound,
    () => _download(sound).whenComplete(() {
      _inFlight.remove(sound);
    }),
  );

  Future<void> _download(ClientSound sound) async {
    try {
      final file = await _fileFor(sound);
      if (file == null || file.existsSync()) return;
      final bytes = await _fetcher.fetch(
        Uri.parse('$discordSoundHost${discordSoundFiles[sound.discordName]}'),
      );
      if (bytes.isEmpty) return;
      await file.parent.create(recursive: true);
      // Written aside and renamed, so a half-written file is never played.
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
    } on Object catch (error) {
      AppLog.warning(
        'sounds',
        '${sound.discordName} not fetched',
        error: error,
      );
    }
  }

  Future<File?> _fileFor(ClientSound sound) async {
    final name = discordSoundFiles[sound.discordName];
    if (name == null) return null;
    return File('${(await _directory()).path}/$name');
  }
}
