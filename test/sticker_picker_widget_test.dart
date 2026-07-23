import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/sticker_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('searches, caps selection, and retains a failed send', (
    tester,
  ) async {
    final result = Completer<bool>();
    List<String>? submitted;
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _PickerApp(
        onSend: (ids) {
          submitted = ids;
          return result.future;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sticker-search')),
      'deploy',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('sticker-option-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('sticker-option-1')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('sticker-search')), '');
    await tester.pump();
    for (final id in ['1', '2', '3', '4']) {
      await tester.tap(find.byKey(ValueKey('sticker-option-$id')));
      await tester.pump();
    }
    expect(find.text('3/3 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send-stickers')));
    await tester.pump();
    expect(submitted, ['1', '2', '3']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    result.complete(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('sticker-picker')), findsOneWidget);
    expect(find.text('Could not send stickers.'), findsOneWidget);
  });
}

class _PickerApp extends StatelessWidget {
  const _PickerApp({required this.onSend});

  final SendStickersCallback onSend;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: StickerPickerButton(
          stickers: _stickers,
          isSending: false,
          onSend: onSend,
          assetBuilder: (_, sticker) =>
              ColoredBox(color: Colors.green, child: Text(sticker.name)),
        ),
      ),
    ),
  );
}

final _stickers = [
  for (var index = 1; index <= 4; index++)
    GuildSticker(
      item: MessageSticker(
        id: '$index',
        name: 'Sticker $index',
        format: StickerFormat.png,
        url: 'https://invalid.example/$index.png',
      ),
      spaceId: 'guild-1',
      tags: index == 2 ? const ['deploy'] : const ['signal'],
      available: true,
    ),
];
