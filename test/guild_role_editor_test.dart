import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/profile_image_picker.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_roles_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'package:flucord/src/presentation/widgets/guild_settings_controls.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  test('the editor offers every named permission bit', () {
    final offered = DiscordPermissions.combine(
      GuildRoleEditor.editable.map((entry) => entry.$2),
    );
    // One toggle per named constant, and nothing invented: bit 47 has no name,
    // so it has no switch either.
    expect(GuildRoleEditor.editable, hasLength(53));
    expect(offered, DiscordPermissions.all);
    expect(
      GuildRoleEditor.editable.toSet(),
      hasLength(53),
      reason: 'a bit listed twice would render two switches',
    );
  });

  testWidgets('sends colour, icon and a high permission bit on save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    // PIN_MESSAGES rides along so the toggle is one the moderator may press:
    // a permission the account does not hold is locked, by design.
    final workspace = guildWorkspace(
      moderatorPermissions:
          allModerationPermissions | DiscordPermissions.pinMessages,
    );
    final controller = GuildSettingsController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
    );
    addTearDown(controller.dispose);
    await controller.openSection(GuildSettingsSection.roles);
    final role = controller.roles.firstWhere((item) => item.id == 'member');

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GuildRoleEditor(
            controller: controller,
            role: role,
            imagePicker: _FakePicker(
              'data:image/png;base64,${base64Encode(List.filled(8, 0x89))}',
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    // A colour straight from the swatch row.
    final swatch = find.byKey(const ValueKey('guild-role-colour-${0x3498db}'));
    await _reveal(tester, swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    // An icon picked from the file dialog the fake answers.
    final pickIcon = find.byKey(const ValueKey('guild-role-icon-pick'));
    await _reveal(tester, pickIcon);
    await tester.tap(pickIcon);
    await tester.pumpAndSettle();
    // A permission no 14-toggle grid ever carried.
    final pin = find.byKey(
      const ValueKey('guild-role-permission-Pin messages'),
    );
    await _reveal(tester, pin);
    expect(pin, findsOneWidget);
    await tester.tap(pin);
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('guild-role-save'));
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.calls, contains('updateRole'));
    final edit = repository.lastRoleEdit!;
    expect(edit['color'], 0x3498db);
    expect((edit['colors'] as Map<String, Object?>)['primary_color'], 0x3498db);
    expect(edit['icon'], startsWith('data:image/png;base64,'));
    // A bit above 2^53, sent as a decimal string because a JSON number would
    // round it away.
    expect(edit['permissions'], DiscordPermissions.pinMessages.toString());
  });

  testWidgets('clearing the icon sends an explicit null', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace();
    final controller = GuildSettingsController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
    );
    addTearDown(controller.dispose);
    await controller.openSection(GuildSettingsSection.roles);
    final role = GuildRole(
      id: 'member',
      guildId: guildId,
      name: 'member',
      position: 1,
      permissions: BigInt.zero,
      iconHash: 'existing',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GuildRoleEditor(
            controller: controller,
            role: role,
            imagePicker: _FakePicker(null),
            onClose: () {},
          ),
        ),
      ),
    );

    await _reveal(tester, find.byKey(const ValueKey('guild-role-icon-clear')));
    await tester.tap(find.byKey(const ValueKey('guild-role-icon-clear')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('guild-role-save')));
    await tester.tap(find.byKey(const ValueKey('guild-role-save')));
    await tester.pumpAndSettle();

    final edit = repository.lastRoleEdit!;
    expect(edit['icon'], isNull);
  });
}

/// Scrolls the editor until [finder] has been built, the same way the
/// settings widget tests do.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(GuildSettingsPanel), const Offset(0, -200));
    await tester.pumpAndSettle();
  }
}

final class _FakePicker implements ProfileImagePicker {
  const _FakePicker(this.dataUri);

  final String? dataUri;

  @override
  Future<ProfileImageSelection?> pick() async => dataUri == null
      ? null
      : ProfileImageSelection(name: 'icon', dataUri: dataUri!, byteCount: 8);
}
