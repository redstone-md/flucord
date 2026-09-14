import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
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

  testWidgets('the channel editor exposes and saves every field', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-channels')),
    );
    await tester.pumpAndSettle();

    // The voice channel carries the voice-only fields.
    await tester.tap(
      find.byKey(const ValueKey('guild-channel-edit-234567890123456789')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit workbench'), findsOneWidget);
    for (final key in [
      'guild-channel-age-gate',
      'guild-channel-slowmode',
      'guild-channel-parent',
      'guild-channel-bitrate',
      'guild-channel-user-limit',
      'guild-channel-region',
    ]) {
      await _reveal(tester, find.byKey(ValueKey(key)));
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    await _reveal(tester, find.byKey(const ValueKey('guild-channel-age-gate')));
    await tester.tap(find.byKey(const ValueKey('guild-channel-age-gate')));
    await tester.pumpAndSettle();
    await _choose(tester, 'guild-channel-slowmode', '5 minutes');
    await _choose(tester, 'guild-channel-parent', 'No category');
    await _choose(tester, 'guild-channel-bitrate', '128 kbps');
    await _choose(tester, 'guild-channel-user-limit', '25');
    await _choose(tester, 'guild-channel-region', 'us-east');
    await _reveal(tester, find.byKey(const ValueKey('guild-channel-save')));
    await tester.tap(find.byKey(const ValueKey('guild-channel-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('editGuildChannel'));
    // Saving closes the editor and returns to the list.
    expect(find.byKey(const ValueKey('guild-channel-create')), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the overwrite editor adds a role overwrite and saves it', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-channels')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('guild-channel-edit-$textChannelId')),
    );
    await tester.pumpAndSettle();

    // The text channel starts with no overwrites. A member overwrite is
    // added through its own picker, named by the member it grants.
    await _reveal(
      tester,
      find.byKey(const ValueKey('guild-overwrite-add-member')),
    );
    await tester.tap(find.byKey(const ValueKey('guild-overwrite-add-member')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('overwrite-target-$lowMemberId')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-overwrite-$lowMemberId')),
      findsOneWidget,
    );

    // Grant View channel to the member.
    await tester.tap(
      find.byKey(const ValueKey('guild-overwrite-edit-$lowMemberId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('overwrite-allow-View channel')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overwrite-bits-done')));
    await tester.pumpAndSettle();

    await _reveal(tester, find.byKey(const ValueKey('guild-channel-save')));
    await tester.tap(find.byKey(const ValueKey('guild-channel-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.savedOverwrites, hasLength(1));
    final saved = harness.repository.savedOverwrites!.single;
    expect(saved.id, lowMemberId);
    expect(saved.kind, PermissionOverwriteKind.member);
    expect(saved.allow, DiscordPermissions.viewChannel);
    harness.dispose();
  });

  testWidgets('the webhooks page lists, creates, edits and deletes', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('guild-settings-rail-webhooks')),
    );
    await tester.pumpAndSettle();
    expect(find.text('There are no webhooks yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-webhook-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('webhook-name')),
      'builds',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('webhook-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('createWebhook'));
    expect(
      find.byKey(const ValueKey('guild-webhook-555555555555555555')),
      findsOneWidget,
    );
    expect(find.text('Posts into #general'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('guild-webhook-edit-555555555555555555')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('webhook-name')),
      'builds v2',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('webhook-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('updateWebhook'));
    expect(find.text('builds v2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('guild-webhook-delete-555555555555555555')),
    );
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('deleteWebhook'));
    expect(find.text('There are no webhooks yet.'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the webhooks page is hidden without MANAGE_WEBHOOKS', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      permissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.manageGuild,
        DiscordPermissions.banMembers,
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guild-settings-rail-webhooks')),
      findsNothing,
    );
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
    // The strip scrolls sideways, so each chip is dragged into view along
    // the strip's own axis.
    for (final section in harness.controller.availableSections) {
      final chip = find.byKey(ValueKey('guild-settings-chip-${section.name}'));
      for (var attempt = 0; attempt < 20; attempt++) {
        if (chip.evaluate().isNotEmpty) {
          final rect = tester.getRect(chip);
          if (rect.left >= 0 && rect.right <= 420) break;
        }
        await tester.drag(
          find
              .descendant(
                of: find.byKey(const ValueKey('guild-settings-section-strip')),
                matching: find.byType(Scrollable),
              )
              .first,
          const Offset(-80, 0),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: section.name);
    }
    harness.dispose();
  });
}

/// Scrolls the open section until [finder] is fully on screen.
///
/// The dialog caps its own height, so a row can be laid out inside the window
/// and still be clipped by the panel it scrolls in; the check is against the
/// panel's own rect, and anything outside it cannot be tapped.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final viewport = find.byType(GuildSettingsPanel);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final view = tester.getRect(viewport);
      final rect = tester.getRect(finder);
      if (rect.top >= view.top && rect.bottom <= view.bottom) break;
    }
    final above =
        finder.evaluate().isNotEmpty &&
        tester.getRect(finder).top < tester.getRect(viewport).top;
    await tester.drag(viewport, Offset(0, above ? 200 : -200));
    await tester.pumpAndSettle();
  }
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
  // The view is configured too, not just the surface: hit testing runs
  // against the view, and a control laid out below the view's own edge
  // cannot be tapped however tall the surface is.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
