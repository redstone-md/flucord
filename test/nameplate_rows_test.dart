import 'dart:ui' as ui;

import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/discord/discord_cdn.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/display_name.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/presentation/widgets/nameplate_backdrop.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contrast.dart';

const _twilight = Nameplate(
  asset: 'nameplates/nameplates/twilight/',
  palette: NameplatePalette.cobalt,
);

const _red = 0xffff0000;
const _blue = 0xff0000ff;

Member _person(String id, {MemberTags tags = MemberTags.none}) => Member(
  id: id,
  displayName: '${id[0].toUpperCase()}${id.substring(1)}',
  initials: id[0].toUpperCase(),
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff59636a,
  spaceIds: const {'guild-1'},
  tags: tags,
);

Finder _in(Finder row, Finder matching) =>
    find.descendant(of: row, matching: matching);

Finder _nameplatePicture(Finder row) => _in(
  row,
  find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url ==
            DiscordCdn.nameplate(_twilight.asset),
  ),
);

Future<void> _pumpMembers(WidgetTester tester, List<Member> members) =>
    tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                MemberSidebar(members: members, spaceId: 'guild-1'),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _pumpDirectMessages(WidgetTester tester, Member person) {
  final workspace = ChatWorkspace(
    spaces: const [CommunitySpace.directMessages()],
    channels: [
      ConversationChannel(
        id: 'dm-${person.id}',
        spaceId: CommunitySpace.directMessagesId,
        name: person.displayName,
        topic: '',
        kind: ChannelKind.text,
        recipientIds: [person.id],
      ),
    ],
    members: [
      const Member(
        id: 'me',
        displayName: 'Ada',
        initials: 'A',
        role: 'Member',
        presence: Presence.online,
        colorValue: 0xff456b5a,
      ),
      person,
    ],
    messages: const [],
    currentMemberId: 'me',
  );
  return tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChannelSidebar(
              space: workspace.spaceById(CommunitySpace.directMessagesId),
              channels: workspace.channelsFor(CommunitySpace.directMessagesId),
              selectedChannelId: null,
              onSelectChannel: (_) {},
              sessionMode: SessionMode.discord,
              connectionStatus: RepositoryConnectionStatus.connected,
              categories: const [],
              currentMember: workspace.memberById(workspace.currentMemberId),
              memberOf: workspace.memberOrNull,
              channelOf: workspace.channelOrNull,
              collapsedCategoryIds: const {},
              onToggleCategory: (_) {},
              onNewDirectMessage: () {},
              onAcceptMessageRequest: (_) {},
              onDeclineMessageRequest: (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpName(
  WidgetTester tester,
  NameStyle? style, {
  bool inServer = false,
  int? roleColor,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('name'),
          child: DisplayName(
            'Freez',
            style: FlucordTextRole.label.style.copyWith(color: Colors.white),
            nameStyle: style,
            inServer: inServer,
            roleColor: roleColor,
          ),
        ),
      ),
    ),
  ),
);

/// The colour [boundary] paints at [point], in its own coordinates.
Future<Color> _pixel(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  Offset point,
) async {
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final offset =
      (point.dy.floor() * boundary.size.width.toInt() + point.dx.floor()) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// The colour of the pixel at [fraction] across the middle of the name.
Future<Color> _pixelAt(WidgetTester tester, double fraction) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('name')),
  );
  final size = boundary.size;
  return _pixel(
    tester,
    boundary,
    Offset(size.width * fraction, size.height / 2),
  );
}

/// The colour on screen at [point].
Future<Color> _screenPixel(WidgetTester tester, Offset point) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screen')),
  );
  return _pixel(tester, boundary, point);
}

Color _drawnColorOf(WidgetTester tester) =>
    tester.widget<Text>(find.text('Freez')).style!.color!;

void main() {
  group('a nameplate', () {
    testWidgets('stands behind a member row, against its end', (tester) async {
      await _pumpMembers(tester, [
        _person('mira', tags: const MemberTags(nameplate: _twilight)),
      ]);

      final row = find.byKey(const ValueKey('member-row-mira'));
      final picture = _nameplatePicture(row);
      expect(picture, findsOneWidget);
      final rowRect = tester.getRect(row);
      final pictureRect = tester.getRect(picture);
      expect(pictureRect.height, rowRect.height);
      expect(pictureRect.width, closeTo(rowRect.height * 16 / 3, 0.01));
      expect(pictureRect.right, rowRect.right);
      expect(
        _in(row, find.byType(ClipRRect)),
        findsWidgets,
        reason: 'the picture is cut to the row shape',
      );
    });

    testWidgets('is held back under the name and shows after it', (
      tester,
    ) async {
      await _pumpMembers(tester, [
        _person(
          'mira',
          tags: const MemberTags(
            nameplate: Nameplate(
              asset: 'nameplates/nameplates/twilight/',
              palette: NameplatePalette.white,
            ),
          ),
        ),
      ]);
      final surface = FlucordTheme.dark
          .extension<FlucordSurfaceTheme>()!
          .surface;
      final row = tester.getRect(find.byKey(const ValueKey('member-row-mira')));
      final name = tester.getRect(find.text('Mira'));

      final underName = await _screenPixel(
        tester,
        Offset(name.center.dx, row.top + 4),
      );
      final atTheEnd = await _screenPixel(
        tester,
        Offset(row.right - 4, row.center.dy),
      );

      expect(underName, surface);
      expect(atTheEnd, isNot(surface));
    });

    testWidgets('stands behind a DM row', (tester) async {
      await _pumpDirectMessages(
        tester,
        _person('jack', tags: const MemberTags(nameplate: _twilight)),
      );

      final row = find.byKey(const ValueKey('channel-dm-jack'));
      expect(_nameplatePicture(row), findsOneWidget);
      expect(
        tester.getRect(_nameplatePicture(row)).right,
        tester.getRect(row).right,
      );
    });

    testWidgets('a person without one gets a plain row', (tester) async {
      await _pumpMembers(tester, [_person('mira')]);

      final row = find.byKey(const ValueKey('member-row-mira'));
      expect(_in(row, find.byType(NameplateBackdrop)), findsNothing);
    });

    test('keeps the row text readable in every palette', () {
      for (final theme in [FlucordTheme.dark, FlucordTheme.light]) {
        final surfaces = theme.extension<FlucordSurfaceTheme>()!;
        final quietRail = Color.alphaBlend(surfaces.quietFill, surfaces.rail);
        // Each state a row can be in: what it sits on, and the text on it.
        final states = [
          // A member row at rest or under the pointer: the name, and the
          // muted activity line.
          (
            NameplatePlacement.memberList,
            hovered: true,
            selected: false,
            under: surfaces.surface,
            texts: [surfaces.text, surfaces.muted],
          ),
          // A member whose card is open: the row is filled with raised.
          (
            NameplatePlacement.memberList,
            hovered: true,
            selected: true,
            under: surfaces.raised,
            texts: [surfaces.text, surfaces.muted],
          ),
          // A DM at rest is muted, an unread one full strength.
          (
            NameplatePlacement.directMessages,
            hovered: false,
            selected: false,
            under: surfaces.rail,
            texts: [surfaces.text, surfaces.muted],
          ),
          // The open DM is filled quietly, with full strength text and a
          // muted activity line.
          (
            NameplatePlacement.directMessages,
            hovered: false,
            selected: true,
            under: quietRail,
            texts: [surfaces.text, surfaces.muted],
          ),
        ];
        for (final palette in NameplatePalette.values) {
          for (final (placement, :hovered, :selected, :under, :texts)
              in states) {
            final wash = NameplateWash(
              palette,
              brightness: theme.brightness,
              placement: placement,
              hovered: hovered,
              selected: selected,
            );
            final background = Color.alphaBlend(wash.strongestUnderText, under);
            for (final text in texts) {
              expect(
                contrast(text, background),
                greaterThanOrEqualTo(4.5),
                reason:
                    '${palette.name} in ${theme.brightness.name} '
                    '${placement.name}, selected: $selected',
              );
            }
          }
        }
      }
    });
  });

  group('a display name', () {
    testWidgets('in one colour is solid', (tester) async {
      await _pumpName(
        tester,
        const NameStyle(colors: [_red], fontId: 11, effectId: 1),
      );

      expect(_drawnColorOf(tester), const Color(_red));
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('in several colours is a gradient across the name', (
      tester,
    ) async {
      await _pumpName(
        tester,
        const NameStyle(colors: [_red, _blue], fontId: 11, effectId: 2),
      );

      final start = await _pixelAt(tester, 0.05);
      final end = await _pixelAt(tester, 0.95);
      expect(start.r, greaterThan(start.b));
      expect(end.b, greaterThan(end.r));
    });

    testWidgets('with a font this client cannot draw keeps the app font', (
      tester,
    ) async {
      await _pumpName(
        tester,
        const NameStyle(colors: [_red], fontId: 99, effectId: 1),
      );

      final style = tester.widget<Text>(find.text('Freez')).style!;
      expect(style.fontFamily, FlucordType.family);
      expect(style.color, const Color(_red));
    });

    testWidgets('with an effect this client cannot draw is the plain name', (
      tester,
    ) async {
      await _pumpName(
        tester,
        const NameStyle(colors: [_red], fontId: 11, effectId: 3),
      );

      expect(_drawnColorOf(tester), Colors.white);
    });

    testWidgets('in a server takes the role colour over the style', (
      tester,
    ) async {
      const style = NameStyle(colors: [_red], fontId: 11, effectId: 1);
      await _pumpName(tester, style, inServer: true, roleColor: _blue);
      expect(_drawnColorOf(tester), const Color(_blue));

      await _pumpName(tester, style, inServer: true);
      expect(_drawnColorOf(tester), Colors.white);
    });
  });
}
