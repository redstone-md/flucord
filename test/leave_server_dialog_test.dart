import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/leave_server_dialog.dart';
import 'package:flucord/src/presentation/widgets/rail_tile.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Finder> openFor(WidgetTester tester, CommunitySpace space) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLeaveServerConfirmation(context, space: space),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return find.byKey(const ValueKey('leave-server-card'));
  }

  testWidgets('the card says how big the server is and when you joined', (
    tester,
  ) async {
    final card = await openFor(
      tester,
      CommunitySpace(
        id: 'forge',
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
        memberCount: 12345,
        joinedAt: DateTime(2024, 3, 3, 12),
      ),
    );

    expect(
      find.descendant(
        of: card,
        matching: find.text('12,345 members · Joined Mar 3, 2024'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(RailMonogram)),
      findsOneWidget,
    );
  });

  testWidgets('the card shows only what is known', (tester) async {
    final card = await openFor(
      tester,
      const CommunitySpace(
        id: 'forge',
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
        memberCount: 1,
      ),
    );

    expect(
      find.descendant(of: card, matching: find.text('1 member')),
      findsOneWidget,
    );
  });

  testWidgets('the card has no caption when nothing is known', (tester) async {
    final card = await openFor(
      tester,
      const CommunitySpace(
        id: 'forge',
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
      ),
    );

    expect(
      find.descendant(of: card, matching: find.byType(Text)),
      findsNWidgets(2),
    );
  });

  testWidgets('the card keeps its corner parallel to the server tile', (
    tester,
  ) async {
    final card = await openFor(
      tester,
      const CommunitySpace(
        id: 'forge',
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
      ),
    );

    final box = tester.widget<Container>(card);
    final decoration = box.decoration! as BoxDecoration;
    final tile = tester.widget<ClipRRect>(
      find.descendant(of: card, matching: find.byType(ClipRRect)).first,
    );
    final gap = (box.padding! as EdgeInsets).left;
    expect(decoration.borderRadius, FlucordRadius.framed);
    expect(
      FlucordRadius.framed.topLeft.x,
      (tile.borderRadius as BorderRadius).topLeft.x + gap,
    );
  });
}
