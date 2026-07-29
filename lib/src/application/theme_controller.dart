import 'package:flutter/foundation.dart';

import '../data/theme/file_theme_store.dart';
import '../domain/flucord_palette.dart';

/// The installed themes, and which one is on.
///
/// The built-in pair stays available whatever is installed: a theme that turns
/// out unreadable must leave somebody a way back to a client they can see.
final class ThemeController extends ChangeNotifier {
  ThemeController(this._store);

  final ThemeStore _store;

  List<InstalledTheme> _themes = const [];
  String? _selectedId;
  bool _loaded = false;
  bool _disposed = false;

  List<InstalledTheme> get themes => List.unmodifiable(_themes);

  /// The theme in use, or null when the built-in one is.
  InstalledTheme? get selected {
    for (final theme in _themes) {
      if (theme.id == _selectedId) return theme;
    }
    return null;
  }

  bool get isLoaded => _loaded;

  /// What the client should draw with right now.
  ///
  /// [systemIsDark] decides between the two built-in palettes; an installed
  /// theme carries its own answer and ignores it, because somebody who chose
  /// a dark theme did not ask for it to turn pale at sunrise.
  FlucordPalette paletteFor({required bool systemIsDark}) =>
      selected?.palette ??
      (systemIsDark ? FlucordPalette.dark : FlucordPalette.light);

  Future<void> load() async {
    if (_loaded) return;
    _themes = await _store.loadThemes();
    _selectedId = await _store.loadSelection();
    _loaded = true;
    _notify();
  }

  /// Re-reads the folder, so a theme dropped in while the client is open
  /// appears without a restart — which is how somebody actually installs one.
  Future<void> refresh() async {
    _themes = await _store.loadThemes();
    // A theme that has been deleted stops being the selection rather than
    // leaving the client pointing at a file that is not there.
    if (_selectedId != null && selected == null) {
      _selectedId = null;
      await _store.saveSelection(null);
    }
    _notify();
  }

  Future<void> select(String? themeId) async {
    if (_selectedId == themeId) return;
    _selectedId = themeId;
    _notify();
    await _store.saveSelection(themeId);
  }

  /// Where to put a theme file. Shown so somebody can open the folder.
  Future<String> themeFolderPath() async =>
      (await _store.themeDirectory()).path;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
