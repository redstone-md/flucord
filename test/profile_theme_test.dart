import 'package:flucord/src/domain/flucord_palette.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/profile_card.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// FLUCORD-105: an installed theme never reaches into a themed profile.

const _themed = ProfileCardData(
  userId: '100000000000000002',
  displayName: 'Freez',
  monogram: 'F',
  username: 'freezz5126',
  themeColors: ProfileThemeColors(0x1e1b4b, 0x4c1d95),
);

/// Somebody's installed theme: a bright one with green text.
final _custom = FlucordPalette.light.copyWith(
  raised: 0xffffeedd,
  text: 0xff00aa00,
  muted: 0xff008800,
);

Future<List<Object?>> _lookUnder(WidgetTester tester, ThemeData app) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: app,
      home: const Scaffold(
        body: Center(child: ProfileCard(data: _themed)),
      ),
    ),
  );
  final card = find.byKey(const ValueKey('profile-card'));
  return [
    tester
        .widget<Material>(
          find.descendant(of: card, matching: find.byType(Material)).first,
        )
        .color,
    tester
        .widget<Text>(find.byKey(const ValueKey('profile-card-handle')))
        .style!
        .color,
  ];
}

void main() {
  testWidgets('a custom app theme leaves a themed profile as it was', (
    tester,
  ) async {
    final underDark = await _lookUnder(tester, FlucordTheme.dark);
    final underCustom = await _lookUnder(
      tester,
      FlucordTheme.fromPalette(_custom),
    );

    expect(underCustom, underDark);
    expect(underCustom, isNot(contains(const Color(0xff008800))));
  });
}
