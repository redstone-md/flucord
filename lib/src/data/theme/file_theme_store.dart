import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/flucord_palette.dart';
import 'better_discord_theme_reader.dart';

/// Where installed themes live, and which one is on.
abstract interface class ThemeStore {
  /// The folder themes are dropped into, so somebody can put one there
  /// without the client's help — which is how every BetterDiscord user
  /// already installs one.
  Future<Directory> themeDirectory();

  Future<List<InstalledTheme>> loadThemes();

  /// The id of the theme in use, or null for the built-in one.
  Future<String?> loadSelection();

  Future<void> saveSelection(String? themeId);
}

/// Themes as files in a folder, read on demand.
///
/// A folder rather than a database: this is how BetterDiscord works and how
/// anybody sharing a theme expects it to be installed — you are handed a file
/// and you put it somewhere. A store that demanded an import button would make
/// every existing instruction on the internet wrong.
final class FileThemeStore implements ThemeStore {
  FileThemeStore({Future<Directory> Function()? directory})
    : _support = directory ?? getApplicationSupportDirectory;

  static const folderName = 'themes';
  static const selectionFileName = 'selected-theme.txt';

  final Future<Directory> Function() _support;

  @override
  Future<Directory> themeDirectory() async {
    final directory = Directory(
      '${(await _support()).path}${Platform.pathSeparator}$folderName',
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<List<InstalledTheme>> loadThemes() async {
    final Directory directory;
    try {
      directory = await themeDirectory();
    } on Object {
      // A profile the client cannot write to still runs, with the built-in
      // theme and nothing else.
      return const [];
    }
    final themes = <InstalledTheme>[];
    for (final entry in directory.listSync()) {
      if (entry is! File) continue;
      final theme = await readTheme(entry);
      if (theme != null) themes.add(theme);
    }
    themes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return themes;
  }

  /// Reads one file, or null when it is not a theme.
  ///
  /// The extension decides how it is read: `.theme.css` is BetterDiscord's own
  /// naming and `.json` is Flucord's. Anything else in the folder is somebody
  /// else's file and is left alone rather than guessed at.
  static Future<InstalledTheme?> readTheme(File file) async {
    final name = file.uri.pathSegments.last;
    try {
      final source = await file.readAsString();
      if (name.toLowerCase().endsWith('.css')) {
        final meta = BetterDiscordThemeReader.readMeta(source);
        return InstalledTheme(
          id: name,
          name: meta['name'] ?? _stripExtension(name),
          palette: BetterDiscordThemeReader.readPalette(source),
          author: meta['author'] ?? '',
          version: meta['version'] ?? '',
          description: meta['description'] ?? '',
          source: ThemeSource.betterDiscord,
        );
      }
      if (!name.toLowerCase().endsWith('.json')) return null;
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return InstalledTheme(
        id: name,
        name: '${decoded['name'] ?? _stripExtension(name)}',
        palette: FlucordPalette.fromJson(decoded['palette'] ?? decoded),
        author: '${decoded['author'] ?? ''}',
        version: '${decoded['version'] ?? ''}',
        description: '${decoded['description'] ?? ''}',
      );
    } on Object {
      // A file that cannot be read or parsed is skipped rather than taking
      // the whole list with it: one bad theme must not hide the others.
      return null;
    }
  }

  static String _stripExtension(String name) {
    final dot = name.indexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  @override
  Future<String?> loadSelection() async {
    try {
      final file = await _selectionFile();
      if (!file.existsSync()) return null;
      final id = (await file.readAsString()).trim();
      return id.isEmpty ? null : id;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveSelection(String? themeId) async {
    final file = await _selectionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(themeId ?? '');
  }

  Future<File> _selectionFile() async => File(
    '${(await _support()).path}${Platform.pathSeparator}$selectionFileName',
  );
}
