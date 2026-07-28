import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_audit_section.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_controls.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_dialog.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_overview_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/guild_settings_fixtures.dart';

part 'guild_settings_audit_cases.dart';
part 'guild_settings_automod_widget_cases.dart';

void main() {
  _automodWidgetCases();
  _automodDialogCases();

  testWidgets('lists only the sections the account may open', (tester) async {
    final harness = await _pump(
      tester,
      permissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.banMembers,
        DiscordPermissions.viewAuditLog,
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-settings-rail-bans')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-settings-rail-auditLog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-settings-rail-roles')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('guild-settings-rail-overview')),
      findsNothing,
    );
    // The bans page opened by itself because it is the first one available.
    expect(find.text('Raider'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('shows a locked door when nothing is permitted', (tester) async {
    final harness = await _pump(
      tester,
      permissions: DiscordPermissions.viewChannel,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-settings-forbidden')),
      findsOneWidget,
    );
    harness.dispose();
  });

  testWidgets('saves only the overview fields that changed', (tester) async {
    final harness = await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guild-overview-name')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('guild-overview-name')),
      'Renamed Forge',
    );
    await _reveal(tester, find.byKey(const ValueKey('guild-overview-save')));
    await tester.tap(find.byKey(const ValueKey('guild-overview-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('saveGuildOverview'));
    harness.dispose();
  });

  testWidgets('withholds role controls above the actor', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('guild-settings-rail-roles')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guild-role-moderator')), findsOneWidget);
    // The actor's own role: every control on the row is inert.
    expect(_enabled(tester, 'guild-role-edit-moderator'), isFalse);
    expect(_enabled(tester, 'guild-role-delete-moderator'), isFalse);
    // A role below them is fully editable, except that @everyone below it
    // cannot be displaced.
    expect(_enabled(tester, 'guild-role-edit-member'), isTrue);
    expect(_enabled(tester, 'guild-role-delete-member'), isTrue);
    // @everyone can never be deleted.
    expect(_enabled(tester, 'guild-role-delete-$guildId'), isFalse);
    harness.dispose();
  });

  testWidgets('edits a role through the permission switches', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('guild-settings-rail-roles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guild-role-edit-member')));
    await tester.pumpAndSettle();

    expect(find.text('Edit member'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guild-role-hoist')));
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      find.byKey(const ValueKey('guild-role-permission-Ban members')),
    );
    await tester.tap(
      find.byKey(const ValueKey('guild-role-permission-Ban members')),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('guild-role-save')));
    await tester.tap(find.byKey(const ValueKey('guild-role-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('updateRole'));
    harness.dispose();
  });

  testWidgets('creates and deletes a channel', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-channels')),
    );
    await tester.pumpAndSettle();
    expect(find.text('general'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-channel-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-channel-name')),
      'announcements',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-channel-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('createGuildChannel'));

    await tester.tap(
      find.byKey(const ValueKey('guild-channel-delete-$textChannelId')),
    );
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('deleteGuildChannel'));
    harness.dispose();
  });

  testWidgets('edits a channel and reorders the list', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-channels')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('guild-channel-down-$textChannelId')),
    );
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('reorderGuildChannels'));

    await tester.tap(
      find.byKey(const ValueKey('guild-channel-edit-$textChannelId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit general'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('guild-channel-name')),
      'renamed',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guild-channel-topic')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('guild-channel-slowmode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 seconds').last);
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('guild-channel-save')));
    await tester.tap(find.byKey(const ValueKey('guild-channel-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('editGuildChannel'));
    // Saving closes the editor and returns to the list.
    expect(find.byKey(const ValueKey('guild-channel-create')), findsOneWidget);
    harness.dispose();
  });

  testWidgets('changes every overview control', (tester) async {
    // The section is pumped on its own so the whole form is on screen: the
    // dialog caps its height, and a test that spent its time dragging a
    // ListView would be testing the ListView.
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = guildWorkspace();
    final repository = FakeGuildManagementRepository();
    final controller = GuildSettingsController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
    );
    addTearDown(controller.dispose);
    await controller.openSection(GuildSettingsSection.overview);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => GuildSettingsOverviewSection(
              controller: controller,
              workspace: workspace,
              spaceId: guildId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _choose(tester, 'guild-overview-verification', 'None');
    await _choose(tester, 'guild-overview-content-filter', 'Scan everybody');
    await _choose(tester, 'guild-overview-notifications', 'All messages');
    await _choose(tester, 'guild-overview-afk-channel', 'workbench');
    await _choose(tester, 'guild-overview-afk-timeout', '1 hour');
    await _choose(tester, 'guild-overview-system-channel', 'No channel');
    await tester.tap(
      find.byKey(const ValueKey('guild-overview-suppress-joins')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guild-overview-boost-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guild-overview-save')));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('saveGuildOverview'));
  });

  testWidgets('an overview with no settings says so', (tester) async {
    final workspace = guildWorkspace();
    final controller = GuildSettingsController(
      FakeGuildManagementRepository(),
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GuildSettingsOverviewSection(
            controller: controller,
            workspace: workspace,
            spaceId: guildId,
          ),
        ),
      ),
    );
    expect(find.text('These settings are not available.'), findsOneWidget);
  });

  testWidgets('bans a member and unbans another', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('guild-settings-rail-bans')));
    await tester.pumpAndSettle();
    expect(find.text('Raider'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-ban-open')));
    await tester.pumpAndSettle();
    // Only members the moderator outranks are offered; the admin is absent.
    expect(
      find.byKey(const ValueKey('ban-candidate-$lowMemberId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ban-candidate-$highMemberId')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('ban-candidate-$lowMemberId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ban-reason')), 'Raiding');
    await tester.tap(find.byKey(const ValueKey('ban-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.bannedRequest!.userIds, [lowMemberId]);
    expect(harness.repository.bannedRequest!.reason, 'Raiding');
    expect(
      harness.repository.bannedRequest!.deletion,
      BanMessageDeletion.lastHour,
    );

    await tester.tap(find.byKey(const ValueKey('guild-unban-$bannedUserId')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('unbanMember'));
    harness.dispose();
  });

  testWidgets('creates and revokes an invite', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('guild-settings-rail-invites')));
    await tester.pumpAndSettle();
    expect(find.text('forge'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-invite-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-invite-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('createChannelInvite'));
    expect(find.text('fresh'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-invite-revoke-forge')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('revokeInvite'));
    harness.dispose();
  });

  _auditCases();

  testWidgets('offers a retry when a section will not load', (tester) async {
    final harness = await _pump(tester, failFirstLoad: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guild-settings-retry')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guild-settings-retry')), findsNothing);
    harness.dispose();
  });

  testWidgets('a failed write leaves an inline banner', (tester) async {
    final harness = await _pump(tester);
    await tester.pumpAndSettle();
    harness.repository.failNext = true;
    await tester.enterText(
      find.byKey(const ValueKey('guild-overview-name')),
      'Renamed Forge',
    );
    await _reveal(tester, find.byKey(const ValueKey('guild-overview-save')));
    await tester.tap(find.byKey(const ValueKey('guild-overview-save')));
    await tester.pumpAndSettle();
    // The banner lives at the top of the form, which the reveal scrolled past.
    await tester.drag(find.byType(GuildSettingsPanel), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-settings-action-error')),
      findsOneWidget,
    );
    harness.dispose();
  });

  testWidgets('a compact window swaps the rail for a strip', (tester) async {
    final harness = await _pump(tester, surfaceSize: const Size(420, 620));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-settings-section-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-settings-rail-overview')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    // Every section has to survive the narrow window, not just the first.
    for (final section in GuildSettingsSection.values) {
      final chip = find.byKey(ValueKey('guild-settings-chip-${section.name}'));
      await tester.scrollUntilVisible(
        chip,
        80,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('guild-settings-section-strip')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: section.name);
    }
    harness.dispose();
  });
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

/// Opens the dropdown keyed [key] and picks the entry labelled [option].
Future<void> _choose(WidgetTester tester, String key, String option) async {
  await _reveal(tester, find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Scrolls the open section until [finder] has been built.
///
/// The dialog caps its own height, so a taller test window does not put the
/// bottom of a long form on screen — only scrolling does.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(GuildSettingsPanel), const Offset(0, -200));
    await tester.pumpAndSettle();
  }
}

final class _Harness {
  _Harness(this.controller, this.repository);

  final GuildSettingsController controller;
  final FakeGuildManagementRepository repository;

  void dispose() => controller.dispose();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  BigInt? permissions,
  bool failFirstLoad = false,
  bool fullAuditPage = false,
  Size surfaceSize = const Size(1000, 1600),
}) async {
  // A window tall enough that every control of every section is on screen.
  // The compact case has its own test; here the point is the behaviour, and a
  // test that spends its time dragging a ListView tests the ListView.
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final workspace = guildWorkspace(
    moderatorPermissions: permissions ?? allModerationPermissions,
  );
  final repository = FakeGuildManagementRepository()
    ..failNext = failFirstLoad
    ..fullAuditPage = fullAuditPage;
  final controller = GuildSettingsController(
    repository,
    WorkspacePermissions(
      workspace,
      memberId: moderatorId,
    ).administrationOf(guildId),
    guildId: guildId,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: GuildSettingsDialog(
        controller: controller,
        space: workspace.spaces.single,
        workspace: workspace,
      ),
    ),
  );
  return _Harness(controller, repository);
}
