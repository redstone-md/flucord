import 'dart:async';

import 'package:flucord/src/application/slash_command_controller.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/presentation/widgets/slash_command_list.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    SlashCommandController controller,
    List<String> picked,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => SlashCommandList(
            controller: controller,
            onPicked: () => picked.add('picked'),
          ),
        ),
      ),
    ),
  );

  testWidgets('stays hidden until a slash is typed', (tester) async {
    final repository = _FakeRepository(commands: [_command('ban')]);
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller.show(channelId: 'channel-1');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);

    controller.syncComposer('/b');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slash-command-list')), findsOne);
    expect(find.text('/ban'), findsOne);
  });

  testWidgets('a command with no options runs on the first tap', (
    tester,
  ) async {
    // A command with no description leaves the row nothing to write.
    final repository = _FakeRepository(
      commands: [_command('ping', description: '')],
    );
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    final picked = <String>[];

    await pump(tester, controller, picked);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/p');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slash-command-cmd-ping')));
    await tester.pumpAndSettle();

    expect(repository.invocations.single.command.name, 'ping');
    expect(picked, ['picked']);
  });

  testWidgets('a command with required options asks for them first', (
    tester,
  ) async {
    final repository = _FakeRepository(
      commands: [
        _command(
          'ban',
          options: const [
            ApplicationCommandOption(
              name: 'user',
              type: 6,
              description: 'Who',
              isRequired: true,
            ),
            ApplicationCommandOption(name: 'reason', type: 3),
          ],
        ),
      ],
    );
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    final picked = <String>[];

    await pump(tester, controller, picked);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/b');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slash-command-cmd-ban')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slash-command-options')), findsOne);
    // Nothing filled in, so it cannot be run.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('slash-options-run')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('slash-option-user')),
      ' 42 ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slash-options-run')));
    await tester.pumpAndSettle();

    // Only what was filled in is sent, trimmed.
    expect(repository.invocations.single.values, {'user': '42'});
    expect(picked, ['picked']);
  });

  testWidgets('backing out of the form runs nothing', (tester) async {
    final repository = _FakeRepository(
      commands: [
        _command(
          'ban',
          options: const [
            ApplicationCommandOption(name: 'user', type: 6, isRequired: true),
          ],
        ),
      ],
    );
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/b');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slash-command-cmd-ban')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slash-options-cancel')));
    await tester.pumpAndSettle();

    expect(repository.invocations, isEmpty);
  });

  testWidgets('nothing matching says so', (tester) async {
    final repository = _FakeRepository();
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/zzz');
    await tester.pumpAndSettle();

    expect(find.text('No command matches that.'), findsOne);
  });

  testWidgets('a failed search says the catalogue did not arrive', (
    tester,
  ) async {
    final repository = _FakeRepository(failSearch: true);
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/b');
    await tester.pumpAndSettle();

    expect(find.text('Discord did not return any commands.'), findsOne);
  });

  testWidgets('a search still running shows progress', (tester) async {
    final gate = Completer<void>();
    final repository = _FakeRepository(commands: [_command('ban')], gate: gate);
    final controller = SlashCommandController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/b');
    // The debounce timer has to fire before the search is in flight.
    await tester.pump(Duration.zero);
    await tester.pump();

    expect(find.byKey(const ValueKey('slash-command-loading')), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('/ban'), findsOne);
  });

  testWidgets('a transport that cannot run commands shows nothing', (
    tester,
  ) async {
    final controller = SlashCommandController(
      () => null,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    controller
      ..show(channelId: 'channel-1')
      ..syncComposer('/b');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
  });
}

ApplicationCommand _command(
  String name, {
  List<ApplicationCommandOption> options = const [],
  String? description,
}) => ApplicationCommand(
  id: 'cmd-$name',
  applicationId: 'app-1',
  name: name,
  version: 'v1',
  description: description ?? 'Does $name',
  options: options,
);

final class _FakeRepository implements ApplicationCommandRepository {
  _FakeRepository({
    this.commands = const [],
    this.failSearch = false,
    this.gate,
  });

  final List<ApplicationCommand> commands;
  final bool failSearch;
  final Completer<void>? gate;
  final List<ApplicationCommandInvocation> invocations = [];

  @override
  Future<List<ApplicationCommand>> searchCommands(
    String channelId, {
    String query = '',
    ApplicationCommandType type = ApplicationCommandType.chatInput,
  }) async {
    await gate?.future;
    if (failSearch) throw StateError('unreachable');
    return commands
        .where((command) => command.name.startsWith(query))
        .toList(growable: false);
  }

  @override
  Future<void> invoke(ApplicationCommandInvocation invocation) async =>
      invocations.add(invocation);
}
