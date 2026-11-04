import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

void main() {
  // The icons drawn in Figma frame "B · Linear, вставной холст".
  const frameB = <String, FlucordIconData>{
    'text channel': FlucordIcons.textChannel,
    'voice channel': FlucordIcons.voiceChannel,
    'chevron down': FlucordIcons.chevronDown,
    'chevron right': FlucordIcons.chevronRight,
    'search': FlucordIcons.search,
    'inbox': FlucordIcons.inbox,
    'pin': FlucordIcons.pin,
    'members': FlucordIcons.members,
    'threads': FlucordIcons.threads,
    'mic': FlucordIcons.mic,
    'headphones': FlucordIcons.headphones,
    'settings': FlucordIcons.settings,
    'camera': FlucordIcons.camera,
    'screen share': FlucordIcons.screenShare,
    'hang up': FlucordIcons.hangUp,
    'add': FlucordIcons.add,
    'emoji': FlucordIcons.emoji,
    'reply': FlucordIcons.reply,
    'direct messages': FlucordIcons.directMessages,
    'image': FlucordIcons.image,
    'explore': FlucordIcons.explore,
    'more': FlucordIcons.more,
    'signal': FlucordIcons.signal,
    'mention': FlucordIcons.mention,
    'mail': FlucordIcons.mail,
  };

  Widget host(
    Widget child, {
    TextDirection direction = TextDirection.ltr,
    IconThemeData theme = const IconThemeData(),
  }) {
    return Directionality(
      textDirection: direction,
      child: IconTheme(
        data: theme,
        child: Center(child: child),
      ),
    );
  }

  Future<BytesLoader> pictureOf(WidgetTester tester, Widget icon) async {
    await tester.pumpWidget(host(icon));
    return tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader;
  }

  test('no two meanings share an icon', () {
    final shapes = frameB.values.map((icon) => icon.data).toSet();

    expect(shapes, hasLength(frameB.length));
  });

  testWidgets('takes its size from the icon theme', (tester) async {
    await tester.pumpWidget(
      host(
        const FlucordIcon(FlucordIcons.reply),
        theme: const IconThemeData(size: 18),
      ),
    );

    expect(tester.getSize(find.byType(FlucordIcon)), const Size.square(18));
  });

  testWidgets('a size given at the call site wins over the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FlucordIcon(FlucordIcons.reply, size: 32),
        theme: const IconThemeData(size: 18),
      ),
    );

    expect(tester.getSize(find.byType(FlucordIcon)), const Size.square(32));
  });

  testWidgets('keeps its size and centres in a larger fixed box', (
    tester,
  ) async {
    // As a Material Icon does, so an avatar fallback needs no Center.
    await tester.pumpWidget(
      host(
        const SizedBox.square(
          key: ValueKey('box'),
          dimension: 40,
          child: FlucordIcon(FlucordIcons.person, size: 18),
        ),
      ),
    );
    final glyph = tester.getRect(find.byType(SvgPicture));

    expect(glyph.size, const Size.square(18));
    expect(glyph.center, tester.getCenter(find.byKey(const ValueKey('box'))));
  });

  testWidgets('draws at a 1.75 stroke in the icon theme colour', (
    tester,
  ) async {
    const themed = IconThemeData(color: Color(0xFFA497F8), size: 20);
    await tester.pumpWidget(
      host(const FlucordIcon(FlucordIcons.pin), theme: themed),
    );
    final drawn = tester
        .widget<SvgPicture>(find.byType(SvgPicture))
        .bytesLoader;

    final expected = await pictureOf(
      tester,
      HugeIcon(
        icon: FlucordIcons.pin.data,
        color: const Color(0xFFA497F8),
        size: 20,
        strokeWidth: 1.75,
      ),
    );

    expect(drawn, expected);
  });

  testWidgets('a colour given at the call site wins over the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FlucordIcon(FlucordIcons.pin, color: Color(0xFF616168)),
        theme: const IconThemeData(color: Color(0xFFA497F8)),
      ),
    );
    final drawn = tester
        .widget<SvgPicture>(find.byType(SvgPicture))
        .bytesLoader;

    final expected = await pictureOf(
      tester,
      HugeIcon(
        icon: FlucordIcons.pin.data,
        color: const Color(0xFF616168),
        strokeWidth: 1.75,
      ),
    );

    expect(drawn, expected);
  });

  testWidgets('icons that point a way mirror in right-to-left text', (
    tester,
  ) async {
    // Material mirrors these three, so the new set must too.
    final mirrored = <String>[];
    for (final MapEntry(key: meaning, value: icon) in frameB.entries) {
      await tester.pumpWidget(
        host(FlucordIcon(icon), direction: TextDirection.rtl),
      );
      final box = tester.renderObject<RenderBox>(find.byType(SvgPicture));
      final bounds = tester.getRect(find.byType(FlucordIcon));
      // A mirrored drawing starts at its right edge.
      if (box.localToGlobal(Offset.zero).dx == bounds.right) {
        mirrored.add(meaning);
      }
    }

    expect(
      mirrored,
      unorderedEquals(['chevron right', 'screen share', 'reply']),
    );
  });

  testWidgets('nothing mirrors in left-to-right text', (tester) async {
    await tester.pumpWidget(host(const FlucordIcon(FlucordIcons.reply)));
    final box = tester.renderObject<RenderBox>(find.byType(SvgPicture));

    expect(
      box.localToGlobal(Offset.zero),
      tester.getTopLeft(find.byType(FlucordIcon)),
    );
  });
}
