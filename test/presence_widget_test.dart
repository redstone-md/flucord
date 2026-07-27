import 'dart:async';

import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/self_presence_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/presentation/widgets/account_panel.dart';
import 'package:flucord/src/presentation/widgets/activity_views.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flucord/src/presentation/widgets/member_profile_popover.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flucord/src/presentation/widgets/self_presence_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

part 'presence_widget_account_panel_cases.dart';
part 'presence_widget_member_panel_cases.dart';

const _me = '111111111111111111';
const _mira = '222222222222222222';
const _roman = '333333333333333333';

final _now = DateTime.utc(2026, 7, 26, 12);

const _game = UserActivity(
  name: 'Elden Ring',
  details: 'Limgrave',
  state: 'Exploring',
  applicationId: '987654321098765432',
  assets: ActivityAssets(
    largeImage: 'cover',
    largeText: 'Elden Ring',
    largeImageUrl: 'https://cdn.example/large.png',
    smallImage: 'class',
    smallText: 'Samurai',
    smallImageUrl: 'https://cdn.example/small.png',
  ),
  party: ActivityParty(currentSize: 2, maxSize: 4),
);

const _custom = UserActivity(
  name: 'Custom Status',
  type: ActivityType.customStatus,
  state: 'Heads down',
  emoji: ActivityEmoji(name: '🛠'),
);

Member _member(String id, String name, {UserPresence? presence}) => Member(
  id: id,
  displayName: name,
  initials: name.substring(0, 2).toUpperCase(),
  role: 'Engineer',
  presence: presence?.status ?? Presence.offline,
  colorValue: 0xff665f82,
  spaceIds: const {'guild-1'},
  rolesBySpace: const {'guild-1': 'Engineer'},
  presenceDetail: presence,
);

/// A presence plane whose writes are recorded rather than sent.
final class _FakePresenceService implements PresenceService {
  final StreamController<SelfPresence> _updates = StreamController.broadcast();
  final List<Presence> statuses = [];
  final List<(String, String, CustomStatusDuration)> customStatuses = [];
  int marks = 0;

  @override
  bool canEdit = true;

  @override
  SelfPresence selfPresence = const SelfPresence();

  @override
  Presence chosenStatus = Presence.online;

  @override
  UserActivity? customStatus;

  @override
  List<UserSession> sessions = const [];

  @override
  Stream<SelfPresence> get selfPresenceUpdates => _updates.stream;

  @override
  Future<void> setStatus(Presence status) async {
    statuses.add(status);
    chosenStatus = status;
    selfPresence = SelfPresence(status: status);
    _updates.add(selfPresence);
  }

  @override
  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  }) async {
    customStatuses.add((text, emojiName, expiry));
  }

  @override
  void markActive() => marks++;

  Future<void> close() => _updates.close();
}

Widget _host(Widget child, {SelfPresenceController? presence}) {
  final body = MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(body: child),
  );
  return presence == null
      ? body
      : SelfPresenceScope(controller: presence, child: body);
}

void main() {
  group('presence indicator', () {
    testWidgets('paints a distinct glyph per status and repaints on change', (
      tester,
    ) async {
      for (final status in Presence.values) {
        await tester.pumpWidget(
          _host(
            Center(
              child: PresenceIndicator(presence: UserPresence(status: status)),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(status.label),
          findsOneWidget,
          reason: '$status must announce itself',
        );
      }
    });

    test('assigns each status its own colour', () {
      expect(PresenceIndicator.colorOf(Presence.online), FlucordColors.success);
      expect(PresenceIndicator.colorOf(Presence.idle), FlucordColors.warning);
      expect(
        PresenceIndicator.colorOf(Presence.doNotDisturb),
        FlucordColors.danger,
      );
      expect(
        PresenceIndicator.colorOf(Presence.streaming),
        FlucordColors.brand,
      );
      expect(
        PresenceIndicator.colorOf(Presence.offline),
        FlucordColors.offline,
      );
      expect(
        PresenceIndicator.colorOf(Presence.invisible),
        FlucordColors.offline,
      );
      expect(
        PresenceIndicator.colorOf(Presence.unknown),
        FlucordColors.offline,
      );
    });

    testWidgets('announces a mobile-only friend as such', (tester) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: PresenceIndicator(
              presence: UserPresence(
                status: Presence.online,
                clientStatus: {ClientPlatform.mobile: Presence.online},
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Online on mobile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a streaming activity turns the dot purple', (tester) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: PresenceIndicator(
              presence: UserPresence(
                status: Presence.online,
                activities: [
                  UserActivity(name: 'Twitch', type: ActivityType.streaming),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Streaming'), findsOneWidget);
    });

    testWidgets('survives a border wider than the dot', (tester) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: PresenceIndicator(
              presence: UserPresence(status: Presence.idle),
              size: 4,
              borderWidth: 6,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('an avatar carries the member presence', (tester) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: MemberAvatar(
              member: _member(
                _mira,
                'Mira',
                presence: const UserPresence(status: Presence.doNotDisturb),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('member-presence-$_mira')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Do Not Disturb'), findsOneWidget);
    });
  });

  group('activity views', () {
    test('formats elapsed and remaining time the way Discord does', () {
      expect(ActivityElapsed.format(const Duration(seconds: 5)), '00:05');
      expect(
        ActivityElapsed.format(const Duration(minutes: 2, seconds: 11)),
        '02:11',
      );
      expect(
        ActivityElapsed.format(
          const Duration(hours: 3, minutes: 4, seconds: 5),
        ),
        '3:04:05',
      );
      expect(ActivityElapsed.line(null, _now), isNull);
      expect(ActivityElapsed.line(const ActivityTimestamps(), _now), isNull);
      expect(
        ActivityElapsed.line(
          ActivityTimestamps(startMs: _now.millisecondsSinceEpoch - 61000),
          _now,
        ),
        '01:01 elapsed',
      );
      expect(
        ActivityElapsed.line(
          ActivityTimestamps(
            endMs: _now.millisecondsSinceEpoch + 61000,
            isCountDown: true,
          ),
          _now,
        ),
        '01:01 left',
      );
      expect(
        ActivityElapsed.line(
          ActivityTimestamps(endMs: _now.millisecondsSinceEpoch + 61000),
          _now,
        ),
        '01:01 left',
      );
      expect(
        ActivityElapsed.line(
          ActivityTimestamps(
            startMs: _now.millisecondsSinceEpoch - 1000,
            endMs: _now.millisecondsSinceEpoch + 1000,
            isCountDown: true,
          ),
          _now,
        ),
        '00:01 left',
      );
    });

    testWidgets('draws the rich presence card with both assets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: ActivityCard(activity: _game, now: _now),
          ),
        ),
      );

      expect(find.text('Elden Ring'), findsOneWidget);
      expect(find.text('Limgrave'), findsOneWidget);
      expect(find.text('Exploring (2 of 4)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('activity-large-image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity-small-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card with no artwork still renders its timing line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: ActivityCard(
              activity: UserActivity(
                name: 'A cup',
                type: ActivityType.competing,
                timestamps: ActivityTimestamps(
                  startMs: _now.millisecondsSinceEpoch - 5000,
                ),
              ),
              now: _now,
            ),
          ),
        ),
      );

      expect(find.text('00:05 elapsed'), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-large-image')), findsNothing);
    });

    testWidgets('a unicode emoji renders beside the status text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Center(child: ActivitySummaryLine(activity: _custom))),
      );

      expect(find.text('🛠'), findsOneWidget);
      expect(find.text('Heads down'), findsOneWidget);
    });

    testWidgets('a custom emoji with no text renders artwork alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: ActivitySummaryLine(
              activity: UserActivity(
                name: 'Custom Status',
                type: ActivityType.customStatus,
                emoji: ActivityEmoji(
                  name: 'shipit',
                  id: '123456789012345678',
                  imageUrl: 'https://cdn.example/emoji.webp',
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('activity-emoji-123456789012345678')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom emoji without artwork falls back to its name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: ActivityEmojiView(
              emoji: ActivityEmoji(name: 'shipit', id: '123456789012345678'),
            ),
          ),
        ),
      );

      expect(find.text('shipit'), findsOneWidget);
    });
  });

  _memberPanelCases();
  _accountPanelCases();
}
