import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/presentation/widgets/guild_automod_rule_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpField(WidgetTester tester, Widget field) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: field)),
  ),
);

void main() {
  testWidgets('a guild with nothing to exempt says so', (tester) async {
    // A rule on a guild whose roles have not arrived, or one with no channels
    // this account can see, still has to render something.
    await _pumpField(
      tester,
      AutoModExemptionField(
        roles: const [],
        channels: const [],
        exemptRoleIds: const [],
        exemptChannelIds: const [],
        onRolesChanged: (_) {},
        onChannelsChanged: (_) {},
      ),
    );

    expect(find.text('No roles to exempt.'), findsOneWidget);
    expect(find.text('No channels to exempt.'), findsOneWidget);
  });

  testWidgets('an exemption is added and removed in place', (tester) async {
    var roleIds = <String>['role-2'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) => AutoModExemptionField(
              roles: const [
                AutoModExemptTarget(id: 'role-1', label: 'mods'),
                AutoModExemptTarget(id: 'role-2', label: 'admins'),
              ],
              channels: const [
                AutoModExemptTarget(id: 'channel-1', label: '#general'),
              ],
              exemptRoleIds: roleIds,
              exemptChannelIds: const [],
              onRolesChanged: (ids) => setState(() => roleIds = ids),
              onChannelsChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('automod-exempt-role-role-1')));
    await tester.pumpAndSettle();
    // Sorted rather than click-ordered, so an unchanged set encodes the same
    // way twice and an edit does not report a change nobody made.
    expect(roleIds, ['role-1', 'role-2']);

    await tester.tap(find.byKey(const ValueKey('automod-exempt-role-role-2')));
    await tester.pumpAndSettle();
    expect(roleIds, ['role-1']);
  });

  testWidgets('a preset already on is shown as on', (tester) async {
    var presets = <AutoModKeywordPreset>[AutoModKeywordPreset.sexualContent];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) => AutoModPresetField(
              selected: presets,
              onChanged: (value) => setState(() => presets = value),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('automod-preset-sexualContent')),
          )
          .value,
      isTrue,
    );
    expect(find.text('Sexual content'), findsOneWidget);
    expect(find.text('Profanity'), findsOneWidget);
    expect(find.text('Slurs'), findsOneWidget);
    // The round-trip placeholder is never offered.
    expect(find.text('Unsupported'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('automod-preset-profanity')));
    await tester.pumpAndSettle();

    // Listed in Discord's own order rather than the order they were ticked.
    expect(presets, [
      AutoModKeywordPreset.profanity,
      AutoModKeywordPreset.sexualContent,
    ]);
  });

  test('every preset has a name the form can show', () {
    for (final preset in AutoModKeywordPreset.values) {
      expect(autoModPresetLabel(preset), isNotEmpty, reason: preset.name);
    }
    expect(autoModPresetLabel(AutoModKeywordPreset.unknown), 'Unsupported');
  });
}
