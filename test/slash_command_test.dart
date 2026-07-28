import 'dart:async';

import 'package:flucord/src/application/slash_command_controller.dart';
import 'package:flucord/src/data/discord/discord_application_command_service.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flutter_test/flutter_test.dart';

const _banCommand = {
  'id': 'cmd-1',
  'application_id': 'app-1',
  'version': 'v1',
  'name': 'ban',
  'description': 'Ban somebody',
  'type': 1,
  'options': [
    {'name': 'user', 'type': 6, 'description': 'Who', 'required': true},
    {'name': 'reason', 'type': 3, 'description': 'Why'},
    // A subcommand is not a value anybody types.
    {'name': 'nested', 'type': 1},
    {'no': 'name'},
  ],
};

void main() {
  group('model', () {
    test('separates the options a caller fills in from subcommands', () {
      final command = DiscordApplicationCommandService.readCommand(
        _banCommand,
      )!;

      expect(command.options.length, 3);
      expect(command.inputs.map((option) => option.name), ['user', 'reason']);
      expect(command.hasRequiredInputs, isTrue);
      expect(command.inputs.first.isRequired, isTrue);
      expect(command.inputs.last.isText, isTrue);
      expect(command.type, ApplicationCommandType.chatInput);
    });

    test('sends only the options that were filled in, in declared order', () {
      final command = DiscordApplicationCommandService.readCommand(
        _banCommand,
      )!;

      final invocation = ApplicationCommandInvocation(
        command: command,
        channelId: 'channel-1',
        values: const {'reason': 'spam', 'user': '42', 'unknown': 'ignored'},
      );

      expect(invocation.optionPayload, [
        {'type': 6, 'name': 'user', 'value': '42'},
        {'type': 3, 'name': 'reason', 'value': 'spam'},
      ]);
      expect(invocation.isComplete, isTrue);
      expect(
        ApplicationCommandInvocation(
          command: command,
          channelId: 'channel-1',
        ).isComplete,
        isFalse,
      );
    });

    test('maps every command type Discord numbers', () {
      expect(
        ApplicationCommandType.fromWire(1),
        ApplicationCommandType.chatInput,
      );
      expect(ApplicationCommandType.fromWire(2), ApplicationCommandType.user);
      expect(
        ApplicationCommandType.fromWire(3),
        ApplicationCommandType.message,
      );
      expect(
        ApplicationCommandType.fromWire(4),
        ApplicationCommandType.primaryEntryPoint,
      );
      expect(
        ApplicationCommandType.fromWire(null),
        ApplicationCommandType.chatInput,
      );
      expect(ApplicationCommandType.message.wireValue, 3);
    });
  });

  group('service', () {
    test('lists the commands a channel offers', () async {
      final transport = _FakeTransport(
        commands: [
          _banCommand,
          // No version means Discord would refuse the invocation.
          {'id': 'cmd-2', 'application_id': 'app-1', 'name': 'stale'},
          {'id': 'cmd-3', 'application_id': 'app-1', 'version': 'v1'},
          {'application_id': 'app-1', 'version': 'v1', 'name': 'no id'},
          {'id': 'cmd-4', 'version': 'v1', 'name': 'no app'},
        ],
      );
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
      );

      final commands = await service.searchCommands('channel-1', query: ' b ');

      expect(commands.map((command) => command.name), ['ban']);
      expect(transport.searches.single, ('channel-1', 'b'));
    });

    test('an invocation echoes the command object back verbatim', () async {
      final transport = _FakeTransport(commands: [_banCommand]);
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
        nonce: () => 'nonce-1',
      );
      final command = (await service.searchCommands('channel-1')).single;

      await service.invoke(
        ApplicationCommandInvocation(
          command: command,
          channelId: 'channel-1',
          guildId: 'guild-1',
          values: const {'user': '42'},
        ),
      );

      final body = transport.interactions.single;
      expect(body['type'], 2);
      expect(body['application_id'], 'app-1');
      expect(body['channel_id'], 'channel-1');
      expect(body['guild_id'], 'guild-1');
      expect(body['session_id'], 'session-1');
      expect(body['nonce'], 'nonce-1');
      final data = body['data']! as Map<String, Object?>;
      expect(data['id'], 'cmd-1');
      expect(data['version'], 'v1');
      expect(data['options'], [
        {'type': 6, 'name': 'user', 'value': '42'},
      ]);
      // Verbatim: a re-serialised command would differ from what Discord sent.
      expect(data['application_command'], _banCommand);
    });

    test('a DM invocation names no guild at all', () async {
      final transport = _FakeTransport(commands: [_banCommand]);
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
      );
      final command = (await service.searchCommands('channel-1')).single;

      await service.invoke(
        ApplicationCommandInvocation(
          command: command,
          channelId: 'dm-1',
          values: const {'user': '42'},
        ),
      );

      expect(transport.interactions.single.containsKey('guild_id'), isFalse);
    });

    test('refuses to send without a session or a required option', () async {
      final transport = _FakeTransport(commands: [_banCommand]);
      var session = '';
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => session.isEmpty ? null : session,
      );
      final command = (await service.searchCommands('channel-1')).single;
      final invocation = ApplicationCommandInvocation(
        command: command,
        channelId: 'channel-1',
        values: const {'user': '42'},
      );

      await expectLater(service.invoke(invocation), throwsA(isA<StateError>()));

      session = 'session-1';
      await expectLater(
        service.invoke(
          ApplicationCommandInvocation(
            command: command,
            channelId: 'channel-1',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.interactions, isEmpty);
    });

    test('every invocation carries its own nonce', () async {
      final transport = _FakeTransport(commands: [_banCommand]);
      final service = DiscordApplicationCommandService(
        transport,
        sessionId: () => 'session-1',
      );
      final command = (await service.searchCommands('channel-1')).single;
      final invocation = ApplicationCommandInvocation(
        command: command,
        channelId: 'channel-1',
        values: const {'user': '42'},
      );

      await service.invoke(invocation);
      await service.invoke(invocation);

      // A retry must not be taken for a second call.
      expect(
        transport.interactions.first['nonce'],
        isNot(transport.interactions.last['nonce']),
      );
    });

    test('a malformed catalogue yields nothing rather than throwing', () async {
      final service = DiscordApplicationCommandService(
        _FakeTransport(rawPayload: {'application_commands': 7}),
        sessionId: () => 'session-1',
      );

      expect(await service.searchCommands('channel-1'), isEmpty);
    });
  });

  group('controller', () {
    test('a transport that cannot run commands offers nothing', () async {
      final controller = SlashCommandController(
        () => null,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller
        ..show(channelId: 'channel-1')
        ..syncComposer('/b');
      await Future<void>.delayed(Duration.zero);

      expect(controller.isSupported, isFalse);
      expect(controller.commands, isEmpty);
    });

    test('opens only for a message that is a command being chosen', () async {
      final repository = _FakeRepository(commands: [_command('ban')]);
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.show(channelId: 'channel-1', guildId: 'guild-1');

      controller.syncComposer('hello');
      expect(controller.isOpen, isFalse);

      controller.syncComposer('/ba');
      expect(controller.isOpen, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.commands.single.name, 'ban');
      expect(repository.searches.single, ('channel-1', 'ba'));

      // Past the first space the command is being filled in, not chosen.
      controller.syncComposer('/ban someone');
      expect(controller.isOpen, isFalse);

      // Reopening on the same query does not search again.
      controller.syncComposer('/ba');
      await Future<void>.delayed(Duration.zero);
      expect(repository.searches.length, 1);
      expect(controller.isOpen, isTrue);
    });

    test('changing channel closes the list', () async {
      final repository = _FakeRepository(commands: [_command('ban')]);
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller
        ..show(channelId: 'channel-1')
        ..syncComposer('/b');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isOpen, isTrue);

      controller.show(channelId: 'channel-2');
      expect(controller.isOpen, isFalse);

      // Showing the same channel twice changes nothing.
      controller.show(channelId: 'channel-2');
      expect(controller.isOpen, isFalse);
    });

    test('invokes in the channel and guild on screen', () async {
      final repository = _FakeRepository(commands: [_command('ban')]);
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller
        ..show(channelId: 'channel-1', guildId: 'guild-1')
        ..syncComposer('/b');
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.invoke(
          controller.commands.single,
          values: const {'reason': 'spam'},
        ),
        isTrue,
      );

      final invocation = repository.invocations.single;
      expect(invocation.channelId, 'channel-1');
      expect(invocation.guildId, 'guild-1');
      expect(invocation.values, {'reason': 'spam'});
      // Running a command closes the list.
      expect(controller.isOpen, isFalse);
    });

    test('a rejected invocation is reported', () async {
      final repository = _FakeRepository(
        commands: [_command('ban')],
        failInvoke: true,
      );
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.show(channelId: 'channel-1');

      expect(await controller.invoke(_command('ban')), isFalse);

      expect(controller.error, isNotNull);
      expect(controller.isSending, isFalse);
    });

    test('an invocation with no channel is refused', () async {
      final repository = _FakeRepository();
      final controller = SlashCommandController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.invoke(_command('ban')), isFalse);
      expect(repository.invocations, isEmpty);
    });

    test('a second invocation while one is in flight is refused', () async {
      final gate = Completer<void>();
      final repository = _FakeRepository(gate: gate);
      final controller = SlashCommandController(() => repository);
      addTearDown(controller.dispose);
      controller.show(channelId: 'channel-1');

      final first = controller.invoke(_command('ban'));
      expect(controller.isSending, isTrue);
      expect(await controller.invoke(_command('ban')), isFalse);

      gate.complete();
      expect(await first, isTrue);
    });

    test('a failed search is reported and clears the list', () async {
      final repository = _FakeRepository(failSearch: true);
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller
        ..show(channelId: 'channel-1')
        ..syncComposer('/b');
      await Future<void>.delayed(Duration.zero);

      expect(controller.error, isNotNull);
      expect(controller.commands, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.query, 'b');
    });

    test('a slower earlier query cannot replace a later one', () async {
      final gate = Completer<void>();
      final repository = _FakeRepository(
        commands: [_command('slow')],
        gate: gate,
      );
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller
        ..show(channelId: 'channel-1')
        ..syncComposer('/s');
      await Future<void>.delayed(Duration.zero);

      repository
        ..gate = null
        ..commands = [_command('fast')];
      controller.syncComposer('/f');
      await Future<void>.delayed(Duration.zero);
      expect(controller.commands.single.name, 'fast');

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.commands.single.name, 'fast');
    });

    test('swapping the transport forgets the old catalogue', () async {
      var repository = _FakeRepository(commands: [_command('old')]);
      final controller = SlashCommandController(
        () => repository,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller
        ..show(channelId: 'channel-1')
        ..syncComposer('/o');
      await Future<void>.delayed(Duration.zero);
      expect(controller.commands.single.name, 'old');

      repository = _FakeRepository(commands: [_command('new')]);

      expect(controller.isSupported, isTrue);
      expect(controller.commands, isEmpty);
    });
  });
}

ApplicationCommand _command(String name) => ApplicationCommand(
  id: 'cmd-$name',
  applicationId: 'app-1',
  name: name,
  version: 'v1',
);

final class _FakeTransport implements DiscordApplicationCommandTransport {
  _FakeTransport({this.commands = const [], this.rawPayload});

  final List<Map<String, Object?>> commands;
  final Map<String, Object?>? rawPayload;
  final List<(String, String)> searches = [];
  final List<Map<String, Object?>> interactions = [];

  @override
  Future<Map<String, Object?>> searchApplicationCommands(
    String channelId, {
    required String query,
  }) async {
    searches.add((channelId, query));
    return rawPayload ?? {'application_commands': commands};
  }

  @override
  Future<void> postInteraction(Map<String, Object?> body) async =>
      interactions.add(body);
}

final class _FakeRepository implements ApplicationCommandRepository {
  _FakeRepository({
    this.commands = const [],
    this.failSearch = false,
    this.failInvoke = false,
    this.gate,
  });

  List<ApplicationCommand> commands;
  final bool failSearch;
  final bool failInvoke;
  Completer<void>? gate;
  final List<(String, String)> searches = [];
  final List<ApplicationCommandInvocation> invocations = [];

  @override
  Future<List<ApplicationCommand>> searchCommands(
    String channelId, {
    String query = '',
  }) async {
    searches.add((channelId, query));
    await gate?.future;
    if (failSearch) throw StateError('unreachable');
    return commands;
  }

  @override
  Future<void> invoke(ApplicationCommandInvocation invocation) async {
    await gate?.future;
    if (failInvoke) throw StateError('rejected');
    invocations.add(invocation);
  }
}
