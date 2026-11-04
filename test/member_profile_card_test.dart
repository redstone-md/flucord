import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/member_profile_card.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/zoomed_app.dart';

void main() {
  testWidgets('under zoom a row above the middle opens its profile downward', (
    tester,
  ) async {
    // 700 high at zoom 1.4 lays out 500 high, so the middle is at 250. The row
    // is at 205 laid out and at 288 drawn, so it is above the middle unless the
    // two are mixed up.
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(builder: await zoomedAppBuilder(1.4)));
    final row = find.byKey(const ValueKey('member-row-222222222222222222'));
    final rowTop = tester.getTopLeft(row).dy;

    await tester.tap(row);
    await tester.pump();

    final popover = find.byKey(const ValueKey('profile-card'));
    expect(tester.getTopLeft(popover).dy, greaterThanOrEqualTo(rowTop - 1));
  });

  testWidgets('opens a member profile and starts a direct message', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Member? recipient;
    String? sent;
    String? copiedId;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedId =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      _host(
        onMessage: (member, text) {
          recipient = member;
          sent = text;
        },
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    // The card fades in, as every profile card does.
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-card')), findsOneWidget);
    expect(find.text('Mira Chen'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Mira Chen profile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-member-id')));
    await tester.pumpAndSettle();
    expect(copiedId, '222222222222222222');

    await tester.enterText(
      find.byKey(const ValueKey('profile-card-message')),
      'see you at nine',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(recipient?.id, '222222222222222222');
    expect(sent, 'see you at nine');
    expect(find.byKey(const ValueKey('profile-card')), findsNothing);
    semantics.dispose();
  });

  testWidgets('dismisses the anchored profile with escape and outside click', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(
      find.byKey(const ValueKey('member-row-333333333333333333')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-card')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-card')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-card')), findsNothing);
  });

  testWidgets('closes an open profile after the workspace changes', (
    tester,
  ) async {
    var spaceId = 'guild-1';
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  MemberSidebar(
                    members: const [_jack, _mira, _roman],
                    spaceId: spaceId,
                    cardFor: _card(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-card')), findsOneWidget);

    updateHost(() => spaceId = 'guild-2');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// The card a row opens, as the shell builds it, with [onMessage] told who
/// was messaged and what was typed.
Widget Function(Member, VoidCallback) _card({
  void Function(Member member, String text)? onMessage,
}) =>
    (member, close) => MemberProfileCard(
      member: member,
      spaceId: 'guild-1',
      onMessage: (text) {
        close();
        onMessage?.call(member, text);
      },
    );

Widget _host({
  void Function(Member member, String text)? onMessage,
  TransitionBuilder? builder,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  builder: builder,
  home: Scaffold(
    body: Row(
      children: [
        const Expanded(child: SizedBox()),
        MemberSidebar(
          members: const [_jack, _mira, _roman],
          spaceId: 'guild-1',
          cardFor: _card(onMessage: onMessage),
        ),
      ],
    ),
  ),
);

const _jack = Member(
  id: '111111111111111111',
  displayName: 'Jack',
  initials: 'JK',
  role: 'Architect',
  presence: Presence.online,
  colorValue: 0xff48745f,
  spaceIds: {'guild-1'},
);

const _mira = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
);

const _roman = Member(
  id: '333333333333333333',
  displayName: 'Roman Vale',
  initials: 'RV',
  role: 'Infrastructure',
  presence: Presence.offline,
  colorValue: 0xff506674,
  spaceIds: {'guild-1'},
);
