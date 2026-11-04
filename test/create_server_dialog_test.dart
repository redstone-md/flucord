import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/disconnected_chat_repository.dart';
import 'package:flucord/src/presentation/widgets/create_server_dialog.dart';
import 'package:flucord/src/presentation/widgets/flucord_button.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    final chat = ChatController(const DisconnectedChatRepository());
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCreateServerDialog(context, chat: chat),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('heads the form like every dialog and labels the name field', (
    tester,
  ) async {
    await open(tester);

    final title = tester.widget<Text>(find.text('Create a server'));
    expect(
      DefaultTextStyle.of(tester.element(find.text('Create a server'))).style
          .merge(title.style)
          .fontSize,
      FlucordTextRole.heading.size,
    );
    // The label sits above the field, not inside it.
    expect(
      tester.getBottomLeft(find.text('Server name')).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('create-server-name-field')))
            .dy,
      ),
    );
    expect(find.text(FlucordKeyHint.escape), findsOneWidget);
    expect(find.text(FlucordKeyHint.enter), findsOneWidget);
  });

  testWidgets('Enter with no name asks for one under the field', (
    tester,
  ) async {
    await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Give the server a name.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Give the server a name.')).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.descendant(
                of: find.byKey(const ValueKey('create-server-name-field')),
                matching: find.byType(EditableText),
              ),
            )
            .dy,
      ),
    );
  });
}
