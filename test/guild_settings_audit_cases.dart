part of 'guild_settings_widget_test.dart';

void _auditCases() {
  testWidgets('renders merged audit entries and filters them', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-auditLog')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Mira updated a channel'), findsOneWidget);
    expect(find.textContaining('(x2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audit-action-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('banned a member').last);
    await tester.pumpAndSettle();
    expect(harness.repository.lastAuditQuery!.action, isNotNull);
    harness.dispose();
  });

  testWidgets('pages the audit log when a full page came back', (tester) async {
    final harness = await _pump(tester, fullAuditPage: true);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-auditLog')),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('audit-load-more')));
    await tester.tap(find.byKey(const ValueKey('audit-load-more')));
    await tester.pumpAndSettle();
    expect(harness.repository.lastAuditQuery!.before, isNotNull);
    harness.dispose();
  });

  testWidgets('an empty audit log says so', (tester) async {
    final harness = await _pump(
      tester,
      permissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.viewAuditLog,
      ]),
    );
    await tester.pumpAndSettle();
    harness.repository.emptyAuditPage = true;
    await harness.controller.load(GuildSettingsSection.auditLog, refresh: true);
    await tester.pumpAndSettle();
    expect(find.text('Nothing has been logged yet.'), findsOneWidget);
    harness.dispose();
  });

  group('audit action labels', () {
    test('names the actions a moderator comes looking for', () {
      expect(
        auditActionLabel(AuditLogActionType.memberBanAdd),
        'banned a member',
      );
      expect(
        auditActionLabel(AuditLogActionType.guildUpdate),
        'updated the server',
      );
      expect(
        auditActionLabel(AuditLogActionType.messageBulkDelete),
        'bulk deleted messages',
      );
      expect(auditActionLabel(AuditLogActionType.roleDelete), 'deleted a role');
      expect(
        auditActionLabel(AuditLogActionType.inviteDelete),
        'revoked an invite',
      );
      expect(
        auditActionLabel(AuditLogActionType.messageUnpin),
        'unpinned a message',
      );
    });

    test('an action with no phrase falls back to its own name', () {
      // Still more use than a bare number, which is all the wire carries.
      expect(
        auditActionLabel(AuditLogActionType.autoModerationQuarantineUser),
        'auto moderation quarantine user',
      );
    });
  });
}
