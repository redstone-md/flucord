import 'package:flucord/src/application/slash_command_controller.dart';
import 'package:flucord/src/data/discord/discord_application_command_service.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/presentation/widgets/application_command_menu.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('service', () {
    test('a context-menu command names what it acts on', () async {
      final transport = _FakeTransport(
        commands: [
          {
            'id': 'cmd-1',
            'application_id': 'app-1',
            'version': 'v1',
            'name': 'Report',
            'type': 3,
          },
        ],
      );
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
      );

      final commands = await service.searchCommands(
        'channel-1',
        type: ApplicationCommandType.message,
      );
      await service.invoke(
        ApplicationCommandInvocation(
          command: commands.single,
          channelId: 'channel-1',
          targetId: 'message-9',
        ),
      );

      // The kind asked for travels in the query, not in the body.
      expect(transport.types.single, 3);
      final data =
          transport.interactions.single['data']! as Map<String, Object?>;
      expect(data['target_id'], 'message-9');
      expect(data['type'], 3);
      expect(data['options'], isEmpty);
    });

    test('a context-menu command is complete once it has a target', () {
      const command = ApplicationCommand(
        id: 'cmd-1',
        applicationId: 'app-1',
        name: 'Report',
        version: 'v1',
        type: ApplicationCommandType.user,
      );

      expect(
        const ApplicationCommandInvocation(
          command: command,
          channelId: 'c',
          targetId: 'user-1',
        ).isComplete,
        isTrue,
      );
      // Without one there is nothing for it to act on.
      expect(
        const ApplicationCommandInvocation(
          command: command,
          channelId: 'c',
        ).isComplete,
        isFalse,
      );
    });

    test('a chat-input command still sends no target', () async {
      final transport = _FakeTransport(
        commands: [
          {
            'id': 'cmd-1',
            'application_id': 'app-1',
            'version': 'v1',
            'name': 'ping',
            'type': 1,
          },
        ],
      );
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
      );
      final command = (await service.searchCommands('channel-1')).single;

      await service.invoke(
        ApplicationCommandInvocation(command: command, channelId: 'channel-1'),
      );

      expect(transport.types.single, 1);
      final data =
          transport.interactions.single['data']! as Map<String, Object?>;
      expect(data.containsKey('target_id'), isFalse);
    });
  });

  group('menu', () {
    Future<void> pump(WidgetTester tester, SlashCommandController controller) =>
        tester.pumpWidget(
          MaterialApp(
            theme: FlucordTheme.dark,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => ApplicationCommandMenuButton(
                  controller: controller,
                  type: ApplicationCommandType.message,
                  targetId: 'message-1',
                ),
              ),
            ),
          ),
        );

    testWidgets('a transport that cannot run commands shows no menu', (
      tester,
    ) async {
      final controller = SlashCommandController(() => null);
      addTearDown(controller.dispose);

      await pump(tester, controller);

      expect(find.byKey(const ValueKey('apps-menu-message-1')), findsNothing);
    });

    testWidgets('runs the command that was chosen on the target', (
      tester,
    ) async {
      final repository = _FakeRepository(
        commands: [
          const ApplicationCommand(
            id: 'cmd-1',
            applicationId: 'app-1',
            name: 'Report',
            version: 'v1',
            description: 'Send this to the moderators',
            type: ApplicationCommandType.message,
          ),
        ],
      );
      final controller = SlashCommandController(() => repository)
        ..show(channelId: 'channel-1', guildId: 'guild-1');
      addTearDown(controller.dispose);

      await pump(tester, controller);
      await tester.tap(find.byKey(const ValueKey('apps-menu-message-1')));
      await tester.pumpAndSettle();

      expect(find.text('Send this to the moderators'), findsOne);
      await tester.tap(find.byKey(const ValueKey('apps-command-cmd-1')));
      await tester.pumpAndSettle();

      final invocation = repository.invocations.single;
      expect(invocation.targetId, 'message-1');
      expect(invocation.command.name, 'Report');
      expect(repository.searchedTypes.single, ApplicationCommandType.message);
    });

    testWidgets('an app offering nothing says so', (tester) async {
      final repository = _FakeRepository();
      final controller = SlashCommandController(() => repository)
        ..show(channelId: 'channel-1');
      addTearDown(controller.dispose);

      await pump(tester, controller);
      await tester.tap(find.byKey(const ValueKey('apps-menu-message-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('apps-empty')), findsOne);
    });

    testWidgets('closing the sheet runs nothing', (tester) async {
      final repository = _FakeRepository(
        commands: [
          const ApplicationCommand(
            id: 'cmd-1',
            applicationId: 'app-1',
            name: 'Report',
            version: 'v1',
            type: ApplicationCommandType.message,
          ),
        ],
      );
      final controller = SlashCommandController(() => repository)
        ..show(channelId: 'channel-1');
      addTearDown(controller.dispose);

      await pump(tester, controller);
      await tester.tap(find.byKey(const ValueKey('apps-menu-message-1')));
      await tester.pumpAndSettle();
      // Tapping the barrier is how a sheet is dismissed.
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(repository.invocations, isEmpty);
    });

    testWidgets('a failed lookup leaves the sheet empty, not broken', (
      tester,
    ) async {
      final repository = _FakeRepository(failSearch: true);
      final controller = SlashCommandController(() => repository)
        ..show(channelId: 'channel-1');
      addTearDown(controller.dispose);

      await pump(tester, controller);
      await tester.tap(find.byKey(const ValueKey('apps-menu-message-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('apps-empty')), findsOne);
      expect(controller.error, isNotNull);
    });

    testWidgets('a menu with no channel on screen offers nothing', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final controller = SlashCommandController(() => repository);
      addTearDown(controller.dispose);

      await pump(tester, controller);
      await tester.tap(find.byKey(const ValueKey('apps-menu-message-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('apps-empty')), findsOne);
      expect(repository.searchedTypes, isEmpty);
    });
  });
}

final class _FakeTransport implements DiscordApplicationCommandTransport {
  _FakeTransport({this.commands = const []});

  final List<Map<String, Object?>> commands;
  final List<int> types = [];
  final List<Map<String, Object?>> interactions = [];

  @override
  Future<Map<String, Object?>> searchApplicationCommands(
    String channelId, {
    required String query,
    required int type,
  }) async {
    types.add(type);
    return {'application_commands': commands};
  }

  @override
  Future<void> postInteraction(Map<String, Object?> body) async =>
      interactions.add(body);
}

final class _FakeRepository implements ApplicationCommandRepository {
  _FakeRepository({this.commands = const [], this.failSearch = false});

  final List<ApplicationCommand> commands;
  final bool failSearch;
  final List<ApplicationCommandType> searchedTypes = [];
  final List<ApplicationCommandInvocation> invocations = [];

  @override
  Future<List<ApplicationCommand>> searchCommands(
    String channelId, {
    String query = '',
    ApplicationCommandType type = ApplicationCommandType.chatInput,
  }) async {
    searchedTypes.add(type);
    if (failSearch) throw StateError('unreachable');
    return commands;
  }

  @override
  Future<void> invoke(ApplicationCommandInvocation invocation) async =>
      invocations.add(invocation);
}
