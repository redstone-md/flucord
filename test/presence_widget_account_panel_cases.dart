part of 'presence_widget_test.dart';

void _accountPanelCases() {
  group('account panel', () {
    late _FakePresenceService service;
    late SelfPresenceController controller;

    setUp(() {
      service = _FakePresenceService();
      controller = SelfPresenceController(() => service)..reconcile();
    });

    tearDown(() async {
      controller.dispose();
      await service.close();
    });

    Widget panel() => _host(
      Column(
        children: [
          const Spacer(),
          AccountPanel(
            member: _member(_me, 'Ada Lovelace'),
            sessionMode: SessionMode.discord,
            connectionStatus: RepositoryConnectionStatus.connected,
          ),
        ],
      ),
      presence: controller,
    );

    testWidgets('shows the broadcast status and offers the picker', (
      tester,
    ) async {
      await tester.pumpWidget(panel());

      expect(find.text('Online'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('self-status-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('self-status-online')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('self-status-doNotDisturb')));
      await tester.pumpAndSettle();

      expect(service.statuses, [Presence.doNotDisturb]);
      expect(find.text('Do Not Disturb'), findsOneWidget);
    });

    testWidgets('renders the custom status instead of the plain status', (
      tester,
    ) async {
      service
        ..customStatus = _custom
        ..selfPresence = const SelfPresence(activities: [_custom]);
      await tester.pumpWidget(panel());

      expect(
        find.byKey(const ValueKey('account-custom-status')),
        findsOneWidget,
      );
      expect(find.text('Heads down'), findsOneWidget);
    });

    testWidgets('writes a custom status through the dialog', (tester) async {
      await tester.pumpWidget(panel());

      await tester.tap(find.byKey(const ValueKey('self-status-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('self-status-custom')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('custom-status-text')),
        'Heads down',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-status-emoji')),
        '🛠',
      );
      await tester.tap(find.byKey(const ValueKey('custom-status-expiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hour').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-status-save')));
      await tester.pumpAndSettle();

      expect(service.customStatuses, [
        ('Heads down', '🛠', CustomStatusDuration.oneHour),
      ]);
    });

    testWidgets('a cancelled dialog writes nothing', (tester) async {
      await tester.pumpWidget(panel());

      await tester.tap(find.byKey(const ValueKey('self-status-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('self-status-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-status-cancel')));
      await tester.pumpAndSettle();

      expect(service.customStatuses, isEmpty);
    });

    testWidgets('clearing a custom status asks for the empty write', (
      tester,
    ) async {
      service.customStatus = _custom;
      await tester.pumpWidget(panel());

      await tester.tap(find.byKey(const ValueKey('self-status-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('self-status-clear-custom')));
      await tester.pumpAndSettle();

      expect(service.customStatuses, [('', '', CustomStatusDuration.never)]);
    });

    testWidgets('a session that cannot edit gets no picker', (tester) async {
      service.canEdit = false;
      await tester.pumpWidget(panel());

      final button = tester.widget<PopupMenuButton<Object>>(
        find.byKey(const ValueKey('self-status-menu')),
      );
      expect(button.enabled, isFalse);
    });

    testWidgets('a transport with no presence plane shows the socket state', (
      tester,
    ) async {
      final empty = SelfPresenceController(() => null)..reconcile();
      addTearDown(empty.dispose);
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              const Spacer(),
              AccountPanel(
                member: _member(_me, 'Ada Lovelace'),
                sessionMode: SessionMode.discord,
                connectionStatus: RepositoryConnectionStatus.connecting,
              ),
            ],
          ),
          presence: empty,
        ),
      );

      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byKey(const ValueKey('self-status-menu')), findsNothing);
    });

    testWidgets('names the transport state for every session mode', (
      tester,
    ) async {
      const cases = {
        (SessionMode.disconnected, RepositoryConnectionStatus.offline):
            'Disconnected',
        (SessionMode.demo, RepositoryConnectionStatus.offline):
            'Demo workspace',
        (SessionMode.discord, RepositoryConnectionStatus.connected):
            'Discord online',
        (SessionMode.discord, RepositoryConnectionStatus.connecting):
            'Connecting...',
        (SessionMode.discord, RepositoryConnectionStatus.reconnecting):
            'Reconnecting...',
        (SessionMode.discord, RepositoryConnectionStatus.offline): 'Offline',
      };
      final empty = SelfPresenceController(() => null)..reconcile();
      addTearDown(empty.dispose);

      for (final entry in cases.entries) {
        await tester.pumpWidget(
          _host(
            Column(
              children: [
                const Spacer(),
                AccountPanel(
                  member: _member(_me, 'Ada Lovelace'),
                  sessionMode: entry.key.$1,
                  connectionStatus: entry.key.$2,
                ),
              ],
            ),
            presence: empty,
          ),
        );

        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('the panel fits a compact window', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      service.customStatus = _custom;

      await tester.pumpWidget(panel());

      expect(tester.takeException(), isNull);
    });
  });
}
