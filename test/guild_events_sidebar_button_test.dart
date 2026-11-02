import 'package:flucord/src/presentation/widgets/guild_events_sidebar_button.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the count is a small badge centred on the row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: GuildEventsSidebarButton(
              count: 3,
              isLoading: false,
              hasError: false,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final badge = tester.getRect(
      find.ancestor(of: find.text('3'), matching: find.byType(Container)).first,
    );
    final row = tester.getRect(
      find.byKey(const ValueKey('guild-events-button')),
    );

    expect(badge.height, lessThanOrEqualTo(20));
    expect(badge.center.dy, row.center.dy);
  });
}
