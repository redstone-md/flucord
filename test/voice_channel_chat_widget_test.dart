import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

const _room = ValueKey('voice-surface-room');
const _chat = ValueKey('voice-surface-chat');

void main() {
  testWidgets('a voice channel offers both the room and its own chat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channel-forge-voice')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Opening a voice channel shows the room; joining it is a button, which
    // is what Discord does.
    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(find.byKey(const ValueKey('toggle-pins')), findsNothing);

    await tester.tap(find.byKey(_chat));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-mute')), findsNothing);
    expect(
      find.text('Bench notes live here while the room is open.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-search')), findsOneWidget);
    // Threads and pins both belong to text channels only: Discord's permission
    // set for a voice channel's chat carries neither, so offering either would
    // only earn a server rejection.
    expect(find.byKey(const ValueKey('toggle-threads')), findsNothing);
    expect(find.byKey(const ValueKey('toggle-pins')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Room notes captured.',
    );
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Room notes captured.'), findsOneWidget);

    await tester.tap(find.byKey(_room));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the surface switch is reachable and operable from the keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(FlucordApp.demo());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('channel-forge-voice')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.widget<InkWell>(find.byKey(_chat)).canRequestFocus, isTrue);
      expect(
        tester.getSemantics(find.byKey(_room)),
        isSemantics(
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
          label: 'Voice room',
        ),
      );
      expect(
        tester.getSemantics(find.byKey(_chat)),
        isSemantics(isSelected: false, label: 'Channel chat'),
      );

      // Focus.of climbs to the enclosing focus node, so ask from inside the
      // segment to land on the one the InkWell itself installed.
      Focus.of(
        tester.element(
          find.descendant(of: find.byKey(_chat), matching: find.byType(Icon)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('message-shaped navigation lands on the voice chat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-m4'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('forward-message-m4')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message-forward-forge-voice')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-forward-submit')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-mute')), findsNothing);
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('forwarded-message')), findsOneWidget);
    expect(
      find.text('Bench notes live here while the room is open.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches surfaces without compact layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice: workbench'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.byKey(_chat));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drops the switch labels in a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice: workbench'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-surface-switch')), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    await tester.tap(find.byKey(_chat));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
