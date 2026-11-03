import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mira = '222222222222222222';
const _guild = 'guild-1';

final _surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

const _game = UserActivity(name: 'Dota 2');

const _custom = UserActivity(
  name: 'Custom Status',
  type: ActivityType.customStatus,
  state: 'Heads down',
  emoji: ActivityEmoji(name: '🛠'),
);

Member _member({List<UserActivity> activities = const []}) => Member(
  id: _mira,
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Engineer',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: const {_guild},
  rolesBySpace: const {_guild: 'Engineer'},
  presenceDetail: UserPresence(status: Presence.online, activities: activities),
);

VoiceParticipantStateEvent _seat(String userId, {String guildId = _guild}) =>
    VoiceParticipantStateEvent(
      userId: userId,
      guildId: guildId,
      channelId: 'voice-1',
      selfMuted: false,
      selfDeafened: false,
      serverMuted: false,
      serverDeafened: false,
      isStreaming: false,
      isVideoEnabled: false,
    );

Future<void> _pump(
  WidgetTester tester,
  Member member, {
  Map<String, List<VoiceParticipantStateEvent>> seats = const {},
  int? Function(Member member)? nameColorOf,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Row(
        children: [
          const Expanded(child: SizedBox()),
          MemberSidebar(
            members: [member],
            spaceId: _guild,
            currentMemberId: 'me',
            onMessage: (_) {},
            seatedByChannel: seats,
            nameColorOf: nameColorOf,
          ),
        ],
      ),
    ),
  ),
);

Finder _icon(FlucordIconData icon) => find.byWidgetPredicate(
  (widget) => widget is FlucordIcon && widget.icon == icon,
);

Finder get _row => find.byKey(const ValueKey('member-row-$_mira'));

Finder get _line => find.byKey(const ValueKey('member-activity-$_mira'));

/// The text of the activity line, as one string.
String _lineText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _line, matching: find.byType(Text)))
    .map((text) => text.data)
    .join(' ');

void main() {
  group('activity line', () {
    testWidgets('a game shows its name and a green gamepad, no verb', (
      tester,
    ) async {
      await _pump(tester, _member(activities: [_game]));

      expect(_lineText(tester), 'Dota 2');
      expect(find.textContaining('Playing'), findsNothing);
      final icon = tester.widget<FlucordIcon>(
        find.descendant(of: _line, matching: _icon(FlucordIcons.game)),
      );
      expect(icon.color, _surfaces.success);
    });

    testWidgets('more activities add a count after the name', (tester) async {
      await _pump(
        tester,
        _member(
          activities: const [
            _game,
            UserActivity(name: 'Spotify', type: ActivityType.listening),
          ],
        ),
      );

      expect(_lineText(tester), 'Dota 2 +1');
    });

    testWidgets('a member in voice here shows a speaker and "In voice"', (
      tester,
    ) async {
      await _pump(
        tester,
        _member(),
        seats: {
          'voice-1': [_seat(_mira)],
        },
      );

      expect(_lineText(tester), 'In voice');
      expect(
        find.descendant(of: _line, matching: _icon(FlucordIcons.voiceChannel)),
        findsOneWidget,
      );
    });

    testWidgets('voice in another server is not shown', (tester) async {
      await _pump(
        tester,
        _member(),
        seats: {
          'voice-9': [_seat(_mira, guildId: 'guild-9')],
        },
      );

      expect(_line, findsNothing);
    });

    testWidgets('watching, streaming and listening show their icon and name', (
      tester,
    ) async {
      const kinds = {
        ActivityType.watching: FlucordIcons.watching,
        ActivityType.streaming: FlucordIcons.streaming,
        ActivityType.listening: FlucordIcons.listening,
      };
      for (final MapEntry(key: type, value: icon) in kinds.entries) {
        await _pump(
          tester,
          _member(
            activities: [UserActivity(name: 'Twitch', type: type)],
          ),
        );

        expect(_lineText(tester), 'Twitch', reason: '$type');
        expect(
          find.descendant(of: _line, matching: _icon(icon)),
          findsOneWidget,
          reason: '$type',
        );
      }
    });

    testWidgets('a custom status shows its emoji and text, no kind icon', (
      tester,
    ) async {
      await _pump(tester, _member(activities: [_custom]));

      expect(_lineText(tester), '🛠 Heads down');
      expect(
        find.descendant(of: _line, matching: find.byType(FlucordIcon)),
        findsNothing,
      );
    });

    testWidgets('a game with a custom status: game icon, then custom text', (
      tester,
    ) async {
      await _pump(tester, _member(activities: [_custom, _game]));

      expect(_lineText(tester), '🛠 Heads down');
      final icon = find.descendant(
        of: _line,
        matching: _icon(FlucordIcons.game),
      );
      expect(icon, findsOneWidget);
      expect(
        tester.getCenter(icon).dx,
        lessThan(tester.getCenter(find.text('Heads down')).dx),
      );
    });

    testWidgets('is one muted caption line, cut with an ellipsis', (
      tester,
    ) async {
      await _pump(
        tester,
        _member(
          activities: const [
            UserActivity(
              name: 'A game whose name is far too long for the member list',
            ),
          ],
        ),
      );

      final text = tester.widget<Text>(
        find.descendant(of: _line, matching: find.byType(Text)),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style?.fontSize, 12);
      expect(text.style?.color, _surfaces.muted);
      expect(
        tester.getRect(_line).right,
        lessThanOrEqualTo(tester.getRect(_row).right),
      );
    });

    testWidgets('nothing to show: no role fallback, name centred', (
      tester,
    ) async {
      await _pump(tester, _member());

      expect(_line, findsNothing);
      expect(find.text('Engineer'), findsNothing);
      expect(
        tester.getCenter(find.text('Mira Chen')).dy,
        moreOrLessEquals(tester.getCenter(_row).dy, epsilon: 0.5),
      );
    });
  });

  group('member row', () {
    testWidgets('is 40 high with a 28 px avatar', (tester) async {
      await _pump(tester, _member(activities: [_game]));

      expect(tester.getSize(_row).height, 40);
      expect(
        tester.getSize(
          find.descendant(of: _row, matching: find.byType(MemberAvatar)),
        ),
        const Size.square(28),
      );
    });

    testWidgets('the status dot has a 2 px ring in the list colour', (
      tester,
    ) async {
      await _pump(tester, _member());

      final dot = tester.widget<PresenceIndicator>(
        find.descendant(of: _row, matching: find.byType(PresenceIndicator)),
      );
      expect(dot.borderWidth, 2);
      expect(dot.borderColor, _surfaces.surface);
    });

    testWidgets('the name keeps its role colour', (tester) async {
      await _pump(tester, _member(), nameColorOf: (_) => 0xffe91e63);

      final name = tester.widget<Text>(find.text('Mira Chen'));
      expect(name.style?.color, const Color(0xffe91e63));
    });
  });

  group('member list', () {
    testWidgets('a 48 px header holds the search field', (tester) async {
      await _pump(tester, _member());

      final field = find.byKey(const ValueKey('member-search'));
      final header = find.byKey(const ValueKey('member-list-header'));
      expect(tester.getSize(header).height, 48);
      expect(find.descendant(of: header, matching: field), findsOneWidget);
      expect(
        find.descendant(of: header, matching: _icon(FlucordIcons.search)),
        findsOneWidget,
      );
    });

    testWidgets('the search field is recessed, with a caption placeholder', (
      tester,
    ) async {
      await _pump(tester, _member());

      final decoration = tester
          .widget<TextField>(find.byKey(const ValueKey('member-search')))
          .decoration!;
      expect(decoration.fillColor, _surfaces.inset);
      expect(decoration.hintText, 'Search members');
      expect(decoration.hintStyle?.fontSize, 12);
      expect(decoration.hintStyle?.color, _surfaces.captionText);
      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, _surfaces.border);
      expect(border.borderSide.width, 1);
      expect(border.borderRadius, FlucordRadius.control);
    });

    testWidgets('a group label has 16 px above and 4 px below', (tester) async {
      await _pump(tester, _member());

      final header = tester.getRect(
        find.byKey(const ValueKey('member-list-header')),
      );
      final label = tester.getRect(find.textContaining('Engineer'));
      expect(label.top - header.bottom, 16);
      expect(tester.getRect(_row).top - label.bottom, 4);
    });

    testWidgets('group labels are captions in the caption tier', (
      tester,
    ) async {
      await _pump(tester, _member());

      final label = tester.widget<Text>(find.textContaining('Engineer'));
      expect(label.style?.fontSize, 12);
      expect(label.style?.fontWeight, FontWeight.w400);
      expect(label.style?.color, _surfaces.captionText);
    });
  });
}
