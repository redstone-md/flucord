import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/nameplate_backdrop.dart';
import 'package:flucord/src/presentation/widgets/profile_card.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = 0xffff0000;

const _freez = Member(
  id: '100000000000000002',
  displayName: 'Freez',
  initials: 'F',
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff456b5a,
  tags: MemberTags(
    nameStyle: NameStyle(colors: [_red], fontId: 11, effectId: 1),
    nameplate: Nameplate(
      asset: 'nameplates/nameplates/twilight/',
      palette: NameplatePalette.cobalt,
    ),
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Color? _nameColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Freez').first).style?.color;

/// The profile card and the full profile window draw the name in its style,
/// and show no nameplate: that stands only behind list rows.
void main() {
  final data = ProfileCardData.member(_freez, spaceId: '200000000000000001');

  testWidgets('the profile card draws the styled name', (tester) async {
    await _pump(tester, ProfileCard(data: data));

    expect(_nameColor(tester), const Color(_red));
    expect(find.byType(NameplateBackdrop), findsNothing);
  });

  testWidgets('the full profile window draws the styled name', (
    tester,
  ) async {
    await _pump(tester, FullProfile(data: data));

    expect(_nameColor(tester), const Color(_red));
    expect(find.byType(NameplateBackdrop), findsNothing);
  });
}
