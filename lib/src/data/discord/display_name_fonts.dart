import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../app_log.dart';

/// The fonts Discord draws a display name in, by `display_name_styles.font_id`.
///
/// Ids and Discord's names for them from its mobile client
/// (`DisplayNameFont.tsx` and `useDisplayNameStylesFont.tsx` in
/// Wumpus-Central/discord-mobile-datamining, read 2026-11-04) and the web
/// client's stylesheet on discord.com the same day, which also gives the
/// weight and the letter spacing. discord-userdoccers (resources/user.mdx,
/// "Display Name Font") names the typeface behind each one.
///
/// Every font here is under the SIL Open Font License and is fetched from
/// Google Fonts in the weight Discord uses. Discord serves its copies as
/// woff2, which Flutter's font loader does not read on every desktop.
///
/// Not drawn, so the name keeps the app font: 7 (Medieval, Néo-Castel, sold
/// on Gumroad), 10 (Vampyre, Sinistre, OFL but published only as a zip),
/// 17 (Pricedown, a campaign font under Typodermic's own licence), the
/// retired 1, 2, 5 and 9, and 11, which is Discord's own font.
enum DisplayNameFont {
  sakura(
    3,
    family: 'Cherry Bomb One',
    letterSpacing: 0.04,
    file: 'cherrybombone/v11/y83DW4od1h6KlV3c6JJhRhGOdhrKDA.ttf',
  ),
  jellybean(4, family: 'Chicle', file: 'chicle/v27/lJwG-pw9i2dqU-BDyQ.ttf'),
  modern(
    6,
    family: 'MuseoModerno',
    letterSpacing: 0.01,
    file:
        'museomoderno/v29/zrf30HnU0_7wWdMrFcWqSEXPVyEaWJ55pTleMmREuew.ttf',
  ),
  eightBit(
    8,
    family: 'Pixelify Sans',
    letterSpacing: 0.02,
    file:
        'pixelifysans/v3/CHy2V-3HFUT7aC4iv1TxGDR9DHEserHN25py2TTp0H1Y.ttf',
  ),
  tempo(
    12,
    family: 'Zilla Slab',
    letterSpacing: 0.03,
    file: 'zillaslab/v12/dFa5ZfeM_74wlPZtksIFYuUe2HQ.ttf',
  ),
  monkeyBars(
    13,
    family: 'Playpen Sans',
    file: 'playpensans/v22/dg43_pj1p6gXP0gzAZgm4c8XQArSU7ACQSn4IhNmunQ.ttf',
  ),
  mainframe(
    14,
    family: 'Orbitron',
    letterSpacing: 0.03,
    file: 'orbitron/v35/yMJMMIlzdpvBhQQL_SC3X9yhF25-T1ny_Cmxpg.ttf',
  ),
  headbang(
    15,
    family: 'New Rocker',
    file: 'newrocker/v17/MwQzbhjp3-HImzcCU_cJkGM.ttf',
  ),
  journal(16, family: 'Kalam', file: 'kalam/v18/YA9Qr0Wd4kDdMtDqHQLL.ttf');

  const DisplayNameFont(
    this.id, {
    required this.family,
    required String file,
    this.letterSpacing = 0,
  }) : _file = file;

  final int id;

  /// The family the font is registered under once loaded.
  final String family;

  /// Discord's letter spacing for it, in ems.
  final double letterSpacing;

  final String _file;

  /// The file on Google Fonts' CDN. Each address names one version of the
  /// font and never changes.
  Uri get url => Uri.https('fonts.gstatic.com', '/s/$_file');

  static DisplayNameFont? byId(int? id) =>
      values.where((font) => font.id == id).firstOrNull;
}

/// Loads [DisplayNameFont]s the first time a name needs one.
///
/// A font is fetched once, kept on disk, and registered with the engine.
/// Registering one makes every paragraph lay out again, so a name already on
/// screen in the app font changes to its own font by itself.
final class DisplayNameFonts {
  DisplayNameFonts({
    Future<Uint8List> Function(Uri url)? fetch,
    Future<void> Function(String family, Uint8List bytes)? register,
  }) : _fetch = fetch ?? _fetchCached,
       _register = register ?? _registerWithEngine;

  final Future<Uint8List> Function(Uri url) _fetch;
  final Future<void> Function(String family, Uint8List bytes) _register;
  final Map<DisplayNameFont, Future<void>> _loads = {};

  /// Starts loading [font] unless it has been asked for already. A font that
  /// failed is not asked for again in this run; the name keeps the app font.
  void request(DisplayNameFont font) =>
      _loads.putIfAbsent(font, () => _load(font));

  /// Completes once [font] is registered, or failed and was logged.
  Future<void> loaded(DisplayNameFont font) {
    request(font);
    return _loads[font]!;
  }

  Future<void> _load(DisplayNameFont font) async {
    try {
      await _register(font.family, await _fetch(font.url));
    } on Object catch (error) {
      AppLog.warning(
        'name-fonts',
        'could not load ${font.family} from ${font.url}',
        error: error,
      );
    }
  }

  static Future<Uint8List> _fetchCached(Uri url) async =>
      (await _NameFontCache.instance.getSingleFile('$url')).readAsBytes();

  static Future<void> _registerWithEngine(String family, Uint8List bytes) =>
      (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

/// The fonts on disk. A handful of files of up to 0.7 MB each, kept a year
/// from last use.
final class _NameFontCache extends CacheManager {
  _NameFontCache._()
    : super(
        Config(
          'flucord_name_fonts',
          stalePeriod: const Duration(days: 365),
          maxNrOfCacheObjects: 32,
        ),
      );

  static final instance = _NameFontCache._();
}
