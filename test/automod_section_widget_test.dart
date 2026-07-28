import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_automod_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  testWidgets('every trigger draws a row of its own', (tester) async {
    // The section on its own rather than inside the settings window: the
    // window caps its own height, so the rows past the cap never build, and
    // the point here is that each trigger builds one.
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final workspace = guildWorkspace();
    final repository = FakeGuildManagementRepository();
    var index = 2;
    for (final trigger in AutoModTriggerType.values) {
      repository.automodRules['rule-$index'] = AutoModRule(
        id: 'rule-$index',
        guildId: guildId,
        name: 'Rule $index',
        eventType: AutoModEventType.messageSend,
        triggerType: trigger,
        metadata: const AutoModTriggerMetadata(mentionTotalLimit: 3),
        actions: const [AutoModAction(type: AutoModActionType.blockMessage)],
      );
      index++;
    }
    final controller = GuildSettingsController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
    );
    addTearDown(controller.dispose);
    await controller.openSection(GuildSettingsSection.automod);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => GuildSettingsAutoModSection(
              controller: controller,
              workspace: workspace,
              spaceId: guildId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var id = 1; id <= AutoModTriggerType.values.length + 1; id++) {
      expect(
        find.byKey(ValueKey('automod-rule-rule-$id')),
        findsOneWidget,
        reason: 'rule-$id',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
