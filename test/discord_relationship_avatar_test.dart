import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/presentation/widgets/discord_relationship_avatar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a friend with no picture shows the monogram a member does', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: DiscordRelationshipAvatar(
            user: DiscordRelationshipUser(id: 'u1', displayName: 'Mira Chen'),
          ),
        ),
      ),
    );

    expect(find.text('MC'), findsOneWidget);
  });
}
