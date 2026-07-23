import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('opens a member profile and starts a direct message', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Member? recipient;
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
    await tester.pumpWidget(_host(onMessage: (member) => recipient = member));

    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );
    expect(find.text('Mira Chen'), findsWidgets);
    expect(find.text('Product design'), findsWidgets);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('222222222222222222'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mira Chen profile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('copy-member-id')));
    await tester.pumpAndSettle();
    expect(copiedId, '222222222222222222');
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message-member')));
    await tester.pump();
    expect(recipient?.id, '222222222222222222');
    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);
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
    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);
  });

  testWidgets('does not offer a direct message to the current member', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(
      find.byKey(const ValueKey('member-row-111111111111111111')),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('message-member')),
    );
    expect(button.onPressed, isNull);
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
                    currentMemberId: _jack.id,
                    onMessage: (_) {},
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
    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );

    updateHost(() => spaceId = 'guild-2');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({ValueChanged<Member>? onMessage}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Row(
      children: [
        const Expanded(child: SizedBox()),
        MemberSidebar(
          members: const [_jack, _mira, _roman],
          spaceId: 'guild-1',
          currentMemberId: _jack.id,
          onMessage: onMessage ?? (_) {},
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
  rolesBySpace: {'guild-1': 'Architect'},
);

const _mira = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Product design'},
);

const _roman = Member(
  id: '333333333333333333',
  displayName: 'Roman Vale',
  initials: 'RV',
  role: 'Infrastructure',
  presence: Presence.offline,
  colorValue: 0xff506674,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Infrastructure'},
);
