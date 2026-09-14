import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

const _animated = CommunitySpace(
  id: 'guild-animated',
  name: 'Forge',
  monogram: 'FO',
  colorValue: 0xff456b5a,
  iconUrl:
      'https://cdn.discordapp.com/icons/guild-animated/a_hash.gif'
      '?size=128',
);

const _still = CommunitySpace(
  id: 'guild-still',
  name: 'Anvil',
  monogram: 'AN',
  colorValue: 0xff456b5a,
  iconUrl: 'https://cdn.discordapp.com/icons/guild-still/hash.webp?size=128',
);

void main() {
  testWidgets('an animated guild icon runs only while hovered', (tester) async {
    await tester.pumpWidget(_rail());

    expect(_iconUrl(tester, _animated.id), endsWith('/a_hash.webp?size=128'));

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(
      tester.getCenter(find.byKey(ValueKey('space-icon-${_animated.id}'))),
    );
    await tester.pump();

    expect(_iconUrl(tester, _animated.id), endsWith('/a_hash.gif?size=128'));

    await pointer.moveTo(Offset.zero);
    await tester.pump();

    expect(_iconUrl(tester, _animated.id), endsWith('/a_hash.webp?size=128'));
  });

  testWidgets('a still guild icon is left alone', (tester) async {
    await tester.pumpWidget(_rail());

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(
      tester.getCenter(find.byKey(ValueKey('space-icon-${_still.id}'))),
    );
    await tester.pump();

    expect(_iconUrl(tester, _still.id), endsWith('/hash.webp?size=128'));
  });
}

Widget _rail() => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: ServerRail(
      spaces: const [_animated, _still],
      activity: const {},
      selectedSpaceId: _animated.id,
      onSelectSpace: (_) {},
      onToggleTheme: () {},
      onOpenConnections: () {},
      sessionMode: SessionMode.discord,
      isDark: true,
    ),
  ),
);

String _iconUrl(WidgetTester tester, String spaceId) {
  final image = tester.widget<Image>(
    find.byKey(ValueKey('space-icon-$spaceId')),
  );
  return (image.image as NetworkImage).url;
}
