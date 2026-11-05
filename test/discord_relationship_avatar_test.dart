import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/presentation/widgets/discord_relationship_avatar.dart';
import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A badge on the avatar says what is known of the person's status, and
/// nothing when nothing is known.
void main() {
  Future<void> pumpAvatar(
    WidgetTester tester,
    DiscordPresenceStatus status,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Center(
        child: DiscordRelationshipAvatar(
          user: DiscordRelationshipUser(
            id: '100000000000000002',
            displayName: 'Mira',
            status: status,
          ),
        ),
      ),
    ),
  );

  testWidgets('an unknown status has no badge', (tester) async {
    await pumpAvatar(tester, DiscordPresenceStatus.unknown);

    expect(find.byType(PresenceIndicator), findsNothing);
  });

  testWidgets('a known status has a badge', (tester) async {
    await pumpAvatar(tester, DiscordPresenceStatus.offline);

    expect(find.byType(PresenceIndicator), findsOneWidget);
  });
}
