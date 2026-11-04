import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_log.dart';

/// The fonts Discord draws a display name in, by `display_name_styles.font_id`.
///
/// Ids, weights and letter spacing from Discord's mobile client
/// (`DisplayNameFont.tsx`, Wumpus-Central/discord-mobile-datamining) and the
/// web client's stylesheet, both read 2026-11-04.
///
/// Not drawn, so the name keeps the app font: 7, 10 and 17 (not on Google
/// Fonts), the retired 1, 2, 5 and 9, and 11, which is Discord's own font.
enum DisplayNameFont {
  sakura(3, family: 'Cherry Bomb One', letterSpacing: 0.04),
  jellybean(4, family: 'Chicle'),
  modern(
    6,
    family: 'MuseoModerno',
    weight: FontWeight.w500,
    letterSpacing: 0.01,
  ),
  eightBit(8, family: 'Pixelify Sans', letterSpacing: 0.02),
  tempo(12, family: 'Zilla Slab', weight: FontWeight.w600, letterSpacing: 0.03),
  monkeyBars(13, family: 'Playpen Sans', weight: FontWeight.w700),
  mainframe(
    14,
    family: 'Orbitron',
    weight: FontWeight.w700,
    letterSpacing: 0.03,
  ),
  headbang(15, family: 'New Rocker'),
  journal(16, family: 'Kalam', weight: FontWeight.w700);

  const DisplayNameFont(
    this.id, {
    required this.family,
    this.weight = FontWeight.w400,
    this.letterSpacing = 0,
  });

  final int id;

  /// The family's name on Google Fonts.
  final String family;

  /// The one weight Discord draws the family in.
  final FontWeight weight;

  /// Discord's letter spacing for it, in ems.
  final double letterSpacing;

  static DisplayNameFont? byId(int? id) =>
      values.where((font) => font.id == id).firstOrNull;
}

/// Loads [DisplayNameFont]s the first time a name needs one.
///
/// google_fonts fetches each file once, checks it, keeps it on disk and
/// registers it with the engine. Listeners hear when a font is ready, so a
/// name on screen in the app font can change to its own.
final class DisplayNameFonts extends ChangeNotifier {
  /// [load] registers a font and answers the family it is drawn under.
  DisplayNameFonts({Future<String> Function(DisplayNameFont font)? load})
    : _load = load ?? _fromGoogleFonts;

  final Future<String> Function(DisplayNameFont font) _load;
  final Map<DisplayNameFont, Future<void>> _loads = {};
  final Map<DisplayNameFont, String> _families = {};

  /// Fonts load one at a time: google_fonts reports loads only all together
  /// ([GoogleFonts.pendingFonts]), so one font failing would read as every
  /// font in flight failing.
  Future<void> _previous = Future.value();

  /// Starts loading [font] unless it has been asked for already. A font that
  /// failed is not asked for again in this run; the name keeps the app font.
  void request(DisplayNameFont font) => _loads.putIfAbsent(
    font,
    () => _previous = _previous.then((_) => _start(font)),
  );

  /// The family [font] is drawn under, or null until it is ready.
  String? familyOf(DisplayNameFont font) => _families[font];

  /// Completes once [font] is ready, or failed and was logged.
  Future<void> loaded(DisplayNameFont font) {
    request(font);
    return _loads[font]!;
  }

  Future<void> _start(DisplayNameFont font) async {
    try {
      _families[font] = await _load(font);
      notifyListeners();
    } on Object catch (error) {
      AppLog.warning(
        'name-fonts',
        'could not load ${font.family}',
        error: error,
      );
    }
  }

  static Future<String> _fromGoogleFonts(DisplayNameFont font) async {
    final style = GoogleFonts.getFont(font.family, fontWeight: font.weight);
    await GoogleFonts.pendingFonts([style]);
    return switch (style.fontFamily) {
      final family? => family,
      null => throw StateError('google_fonts named no family'),
    };
  }
}
