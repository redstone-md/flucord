import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, theme) in [
    ('dark', FlucordTheme.dark),
    ('light', FlucordTheme.light),
  ]) {
    testWidgets('every Material text role in $name is on the type scale', (
      tester,
    ) async {
      late TextTheme roles;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              roles = Theme.of(context).textTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      // Material draws badges, helper text, tabs and menus in these roles,
      // so a role off the scale is a size the app never chose.
      for (final style in [
        roles.displayLarge,
        roles.displayMedium,
        roles.displaySmall,
        roles.headlineLarge,
        roles.headlineMedium,
        roles.headlineSmall,
        roles.titleLarge,
        roles.titleMedium,
        roles.titleSmall,
        roles.bodyLarge,
        roles.bodyMedium,
        roles.bodySmall,
        roles.labelLarge,
        roles.labelMedium,
        roles.labelSmall,
      ]) {
        expect(FlucordType.sizes, contains(style!.fontSize));
        expect(style.fontFamily, FlucordType.family);
      }
    });
  }
}
