import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/application/theme_controller.dart';
import 'package:flucord/src/data/theme/better_discord_theme_reader.dart';
import 'package:flucord/src/data/theme/file_theme_store.dart';
import 'package:flucord/src/domain/flucord_palette.dart';
import 'package:flucord/src/presentation/widgets/theme_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading a BetterDiscord theme', () {
    test('the colours are taken and the rest is left alone', () {
      // The shape every BD theme has: a meta header, then Discord's own
      // variables, then a great deal of CSS about a DOM Flucord has not got.
      const source = '''
/**
 * @name Midnight
 * @author somebody
 * @version 1.2.0
 * @description A dark theme.
 */
:root {
  --background-primary: #101014;
  --background-secondary: #16161c;
  --background-tertiary: #0b0b0f;
  --text-normal: #e8e8f0;
  --text-muted: rgb(140, 140, 160);
  --brand-experiment: #7b5cff;
}
.chat-2ZfjoI { border-radius: 8px; }
''';

      final meta = BetterDiscordThemeReader.readMeta(source);
      final palette = BetterDiscordThemeReader.readPalette(source);

      expect(meta['name'], 'Midnight');
      expect(meta['author'], 'somebody');
      expect(meta['version'], '1.2.0');
      expect(palette.canvas, 0xff101014);
      expect(palette.surface, 0xff16161c);
      expect(palette.rail, 0xff0b0b0f);
      expect(palette.text, 0xffe8e8f0);
      expect(palette.muted, 0xff8c8ca0);
      expect(palette.brand, 0xff7b5cff);
      // Anything the theme said nothing about keeps the built-in colour
      // rather than the theme being refused for being incomplete.
      expect(palette.success, FlucordPalette.dark.success);
    });

    test('a pale background makes it a light theme', () {
      const source = ':root { --background-primary: #fdfdfd; }';

      final palette = BetterDiscordThemeReader.readPalette(source);

      // Read from the luma rather than from a name: a theme called "dark" can
      // be pale, and the icons follow the background either way.
      expect(palette.isDark, isFalse);
      expect(
        BetterDiscordThemeReader.readPalette(
          ':root { --background-primary: #202020; }',
        ).isDark,
        isTrue,
      );
    });

    test('a variable pointing at another is followed', () {
      const source = '''
:root {
  --my-bg: #123456;
  --background-primary: var(--my-bg);
  --background-secondary: var(--absent, #654321);
}
''';

      final palette = BetterDiscordThemeReader.readPalette(source);

      expect(palette.canvas, 0xff123456);
      // A var() carries its own fallback, which is what a theme relies on for
      // a variable Discord stopped shipping.
      expect(palette.surface, 0xff654321);
    });

    test('a chain that never resolves does not hang or lie', () {
      const source = '''
:root {
  --a: var(--b);
  --b: var(--a);
  --background-primary: var(--a);
}
''';

      final palette = BetterDiscordThemeReader.readPalette(source);

      expect(palette.canvas, FlucordPalette.dark.canvas);
    });

    test('the later declaration wins, as the cascade says', () {
      const source = '''
:root { --background-primary: #111111; }
.theme-dark { --background-primary: #222222; }
''';

      expect(
        BetterDiscordThemeReader.readPalette(source).canvas,
        0xff222222,
      );
    });

    test('every colour notation a theme might use is read', () {
      expect(BetterDiscordThemeReader.parseColour('#abc'), 0xffaabbcc);
      expect(BetterDiscordThemeReader.parseColour('#ff8800'), 0xffff8800);
      // CSS writes the alpha last; Flutter wants it first.
      expect(BetterDiscordThemeReader.parseColour('#ff880080'), 0x80ff8800);
      expect(BetterDiscordThemeReader.parseColour('rgb(255, 136, 0)'),
          0xffff8800);
      expect(
        BetterDiscordThemeReader.parseColour('rgba(255, 136, 0, 0.5)'),
        0x80ff8800,
      );
      // Discord writes some of its own variables as a bare triple.
      expect(BetterDiscordThemeReader.parseColour('255, 136, 0'), 0xffff8800);
      expect(BetterDiscordThemeReader.parseColour('nonsense'), isNull);
      expect(BetterDiscordThemeReader.parseColour(''), isNull);
      expect(BetterDiscordThemeReader.parseColour('#12'), isNull);
      expect(BetterDiscordThemeReader.parseColour('rgb(1, 2)'), isNull);
      expect(BetterDiscordThemeReader.parseColour('rgb(a, b, c)'), isNull);
    });

    test('a file with no meta and no variables is still not a crash', () {
      expect(BetterDiscordThemeReader.readMeta('body { color: red; }'), isEmpty);
      expect(
        BetterDiscordThemeReader.readPalette('body { color: red; }').canvas,
        FlucordPalette.dark.canvas,
      );
    });
  });

  group('the palette itself', () {
    test('a stored palette survives a round trip', () {
      final read = FlucordPalette.fromJson(
        jsonDecode(jsonEncode(FlucordPalette.light.toJson())),
      );

      expect(read.canvas, FlucordPalette.light.canvas);
      expect(read.isDark, isFalse);
    });

    test('a partial palette keeps the rest of the fallback', () {
      final read = FlucordPalette.fromJson(
        const {'canvas': 0xff000000, 'text': 'not a colour'},
      );

      expect(read.canvas, 0xff000000);
      expect(read.text, FlucordPalette.dark.text);
      expect(FlucordPalette.fromJson('not a map').canvas,
          FlucordPalette.dark.canvas);
    });

    test('the theme is built from whatever palette it is given', () {
      final theme = FlucordTheme.fromPalette(
        FlucordPalette.dark.copyWith(canvas: 0xff102030, brand: 0xff00ff00),
      );

      // Every colour comes from the palette rather than a constant: a widget
      // reaching for a hard-coded shade would keep Discord's own under
      // somebody else's theme.
      expect(theme.scaffoldBackgroundColor, const Color(0xff102030));
      expect(theme.colorScheme.primary, const Color(0xff00ff00));
      expect(FlucordTheme.fromPalette(FlucordPalette.light).brightness,
          Brightness.light);
    });
  });

  group('the folder', () {
    test('both kinds of file are read, and nothing else is', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-theme');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileThemeStore(directory: () async => directory);
      final themes = await store.themeDirectory();
      File('${themes.path}${Platform.pathSeparator}midnight.theme.css')
          .writeAsStringSync('''
/**
 * @name Midnight
 */
:root { --background-primary: #101014; }
''');
      File('${themes.path}${Platform.pathSeparator}sunrise.json')
          .writeAsStringSync(
        jsonEncode({
          'name': 'Sunrise',
          'author': 'me',
          'palette': {'canvas': 0xfffff5e6, 'is_dark': false},
        }),
      );
      // Somebody else's file in the same folder is left alone rather than
      // guessed at.
      File('${themes.path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('not a theme');
      File('${themes.path}${Platform.pathSeparator}broken.json')
          .writeAsStringSync('{ not json');

      final read = await store.loadThemes();

      expect(read.map((theme) => theme.name), ['Midnight', 'Sunrise']);
      expect(read.first.source, ThemeSource.betterDiscord);
      expect(read.first.palette.canvas, 0xff101014);
      expect(read.last.source, ThemeSource.flucord);
      expect(read.last.palette.canvas, 0xfffff5e6);
      expect(read.last.author, 'me');
    });

    test('the selection is remembered, and forgotten when asked', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-theme');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileThemeStore(directory: () async => directory);

      expect(await store.loadSelection(), isNull);
      await store.saveSelection('midnight.theme.css');
      expect(await store.loadSelection(), 'midnight.theme.css');
      await store.saveSelection(null);
      expect(await store.loadSelection(), isNull);
    });

    test('a profile that cannot be written leaves the built-in theme',
        () async {
      final store = FileThemeStore(
        directory: () async => throw const FileSystemException('nowhere'),
      );

      expect(await store.loadThemes(), isEmpty);
      expect(await store.loadSelection(), isNull);
    });
  });

  group('the controller', () {
    test('nothing installed means the built-in pair', () async {
      final controller = ThemeController(_MemoryStore());
      addTearDown(controller.dispose);

      await controller.load();
      // A second load does not re-read.
      await controller.load();

      expect(controller.selected, isNull);
      expect(controller.paletteFor(systemIsDark: true), FlucordPalette.dark);
      expect(controller.paletteFor(systemIsDark: false), FlucordPalette.light);
    });

    test('a chosen theme answers for both light and dark', () async {
      final store = _MemoryStore()
        ..themes = [
          const InstalledTheme(
            id: 'midnight.json',
            name: 'Midnight',
            palette: FlucordPalette.dark,
          ),
        ];
      final controller = ThemeController(store);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.select('midnight.json');

      // Somebody who chose a dark theme did not ask for it to turn pale when
      // the account setting says light.
      expect(controller.paletteFor(systemIsDark: false), FlucordPalette.dark);
      expect(store.saved, ['midnight.json']);
      // Choosing the same one again writes nothing.
      await controller.select('midnight.json');
      expect(store.saved, hasLength(1));
    });

    test('a theme deleted while the client is open stops being the choice',
        () async {
      final store = _MemoryStore()
        ..themes = [
          const InstalledTheme(
            id: 'midnight.json',
            name: 'Midnight',
            palette: FlucordPalette.dark,
          ),
        ]
        ..selection = 'midnight.json';
      final controller = ThemeController(store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.selected, isNotNull);

      store.themes = const [];
      await controller.refresh();

      expect(controller.selected, isNull);
      // Cleared on disk too, rather than leaving the client pointing at a
      // file that is not there.
      expect(store.saved.last, isNull);
    });

    test('a theme dropped in while the client is open appears', () async {
      final store = _MemoryStore();
      final controller = ThemeController(store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.themes, isEmpty);

      store.themes = [
        const InstalledTheme(
          id: 'new.json',
          name: 'New',
          palette: FlucordPalette.light,
        ),
      ];
      await controller.refresh();

      expect(controller.themes.single.name, 'New');
      expect(await controller.themeFolderPath(), isNotEmpty);
    });
  });

  group('the settings page', () {
    testWidgets('the installed themes are listed and one can be chosen', (
      tester,
    ) async {
      final store = _MemoryStore()
        ..themes = [
          const InstalledTheme(
            id: 'midnight.theme.css',
            name: 'Midnight',
            author: 'somebody',
            version: '1.2.0',
            palette: FlucordPalette.dark,
            source: ThemeSource.betterDiscord,
          ),
        ];
      final controller = ThemeController(store);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThemeSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Said out loud, because a BD theme would otherwise look half-applied
      // and read as a bug.
      expect(find.textContaining('only its colours are read'), findsOneWidget);
      expect(
        find.textContaining('BetterDiscord — colours only'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('theme-midnight.theme.css')));
      await tester.pumpAndSettle();
      expect(controller.selected?.id, 'midnight.theme.css');

      await tester.tap(find.byKey(const ValueKey('theme-builtin')));
      await tester.pumpAndSettle();
      expect(controller.selected, isNull);
    });

    testWidgets('an empty folder says so and can be re-read', (tester) async {
      final store = _MemoryStore();
      final controller = ThemeController(store);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(body: ThemeSection(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('theme-none-installed')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('theme-folder')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('theme-copy-folder')));
      await tester.tap(find.byKey(const ValueKey('theme-refresh')));
      await tester.pumpAndSettle();
      expect(store.reads, greaterThan(1));
    });
  });
}

final class _MemoryStore implements ThemeStore {
  List<InstalledTheme> themes = const [];
  String? selection;
  final List<String?> saved = [];
  int reads = 0;

  @override
  Future<Directory> themeDirectory() async => Directory.systemTemp;

  @override
  Future<List<InstalledTheme>> loadThemes() async {
    reads++;
    return themes;
  }

  @override
  Future<String?> loadSelection() async => selection;

  @override
  Future<void> saveSelection(String? themeId) async {
    selection = themeId;
    saved.add(themeId);
  }
}
