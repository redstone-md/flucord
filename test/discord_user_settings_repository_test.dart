import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/discord/discord_user_settings_repository.dart';
import 'package:flucord/src/data/discord/discord_user_settings_transport.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

void main() {
  group('loading', () {
    test('takes the blob READY hands over without a request', () async {
      final transport = _Transport();
      final repository = DiscordUserSettingsRepository(transport);
      addTearDown(repository.close);
      final seen = <UserSettings>[];
      repository.updates.listen(seen.add);

      repository.acceptGatewayDispatch('READY', {
        'user_settings_proto': _blob(theme: 2),
      });
      await repository.load();
      await pumpEventQueue();

      expect(repository.isLoaded, isTrue);
      expect(repository.current!.appearance.theme, UserSettingsTheme.light);
      expect(transport.reads, isEmpty);
      expect(seen, hasLength(1));
    });

    test('ignores a READY without a settings blob', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);

      repository.acceptGatewayDispatch('READY', const {});
      repository.acceptGatewayDispatch('READY', const {
        'user_settings_proto': '',
      });

      expect(repository.isLoaded, isFalse);
      expect(repository.current, isNull);
    });

    test('fetches over REST when the gateway never delivered one', () async {
      final transport = _Transport(stored: _blob(theme: 1));
      final repository = DiscordUserSettingsRepository(transport);
      addTearDown(repository.close);

      final settings = await repository.load();

      expect(settings.appearance.theme, UserSettingsTheme.dark);
      expect(transport.reads, [1]);
    });

    test('shares one request between concurrent loads', () async {
      final transport = _Transport(stored: _blob(theme: 1));
      final repository = DiscordUserSettingsRepository(transport);
      addTearDown(repository.close);

      await Future.wait([repository.load(), repository.load()]);
      await repository.load();

      expect(transport.reads, hasLength(1));
    });

    test('treats an account with no stored settings as all defaults', () async {
      final transport = _Transport();
      final repository = DiscordUserSettingsRepository(transport);
      addTearDown(repository.close);

      final settings = await repository.load();

      expect(settings.appearance.theme, UserSettingsTheme.unset);
      expect(repository.isLoaded, isTrue);
    });

    test('reports a blob it cannot decode rather than storing junk', () async {
      final transport = _Transport(stored: '!!!!');
      final repository = DiscordUserSettingsRepository(transport);
      addTearDown(repository.close);

      await expectLater(repository.load(), throwsA(isA<DiscordApiException>()));
      expect(repository.isLoaded, isFalse);
    });
  });

  group('dispatches', () {
    test('replaces one group for a partial update', () async {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);
      repository.acceptGatewayDispatch('READY', {
        'user_settings_proto': _blob(theme: 1, quiet: true),
      });

      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 1, 'proto': _blob(theme: 2)},
        'partial': true,
      });

      expect(repository.current!.appearance.theme, UserSettingsTheme.light);
      // The notifications group was not in the partial, so it survived.
      expect(repository.current!.notifications.isQuiet, isTrue);
    });

    test('replaces the whole root when the update is not partial', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);
      repository.acceptGatewayDispatch('READY', {
        'user_settings_proto': _blob(theme: 1, quiet: true),
      });

      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 1, 'proto': _blob(theme: 2)},
      });

      expect(repository.current!.appearance.theme, UserSettingsTheme.light);
      expect(repository.current!.notifications.isQuiet, isFalse);
    });

    test('ignores settings types Flucord has no codec for', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);

      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 2, 'proto': _blob(theme: 2)},
      });
      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 3, 'proto': _blob(theme: 2)},
      });

      expect(repository.isLoaded, isFalse);
    });

    test('ignores a malformed envelope and an unrelated dispatch', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);

      repository.acceptGatewayDispatch('MESSAGE_CREATE', const {});
      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', const {
        'settings': 'nonsense',
      });
      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', const {
        'settings': {'type': 1, 'proto': 7},
      });

      expect(repository.isLoaded, isFalse);
    });

    test('keeps the previous value when a blob will not decode', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);
      repository.acceptGatewayDispatch('READY', {
        'user_settings_proto': _blob(theme: 1),
      });

      repository.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', const {
        'settings': {'type': 1, 'proto': 'AAAAA'},
      });

      expect(repository.current!.appearance.theme, UserSettingsTheme.dark);
    });
  });

  group('writing', () {
    test('refuses an edit before anything has loaded', () {
      final repository = DiscordUserSettingsRepository(_Transport());
      addTearDown(repository.close);

      expect(
        () => repository.apply(
          const UserSettingsPatch(theme: UserSettingsTheme.light),
        ),
        throwsStateError,
      );
    });

    test('ignores an empty patch', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(const UserSettingsPatch());
      await repository.flush();

      expect(transport.writes, isEmpty);
    });

    test('applies optimistically and sends only the edited group', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );

      expect(repository.current!.appearance.theme, UserSettingsTheme.light);
      await repository.flush();
      expect(transport.writes, hasLength(1));
      final sent = DiscordUserSettingsProto.decodeRoot(transport.writes.single);
      expect(
        sent.fields.map((field) => field.number),
        orderedEquals([PreloadedUserSettingsField.appearance]),
      );
      // The stored group's other leaves ride along, because a write replaces
      // the group outright.
      expect(
        sent
            .messageAt(PreloadedUserSettingsField.appearance)!
            .boolAt(AppearanceField.developerMode),
        isTrue,
      );
    });

    test('coalesces edits made before the write leaves', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.apply(
        const UserSettingsPatch(quietMode: true),
        delay: UserSettingsSaveDelay.batched,
      );
      await repository.flush();

      expect(transport.writes, hasLength(1));
      final sent = DiscordUserSettingsProto.decodeRoot(transport.writes.single);
      expect(sent.fields.map((field) => field.number).toSet(), {
        PreloadedUserSettingsField.appearance,
        PreloadedUserSettingsField.notifications,
      });
    });

    test('a deliberate edit overtakes a batched one already waiting', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(quietMode: true),
        delay: UserSettingsSaveDelay.batched,
      );
      expect(transport.writes, isEmpty);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await pumpEventQueue();

      expect(transport.writes, hasLength(1));
    });

    test('flushing with nothing pending sends nothing', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.flush();

      expect(transport.writes, isEmpty);
    });

    test('adopts the merged blob the server answers with', () async {
      final transport = _Transport(response: _blob(theme: 4));
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.flush();

      expect(repository.current!.appearance.theme, UserSettingsTheme.midnight);
      expect(repository.lastWriteError, isNull);
    });

    test('drops changes the server calls out of date', () async {
      final transport = _Transport(response: _blob(theme: 1), outOfDate: true);
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.flush();
      await repository.flush();

      expect(repository.current!.appearance.theme, UserSettingsTheme.dark);
      expect(transport.writes, hasLength(1));
    });

    test(
      'keeps the optimistic value when the server answers nothing',
      () async {
        final transport = _Transport(response: null);
        final repository = _loaded(transport);
        addTearDown(repository.close);

        await repository.apply(
          const UserSettingsPatch(theme: UserSettingsTheme.light),
        );
        await repository.flush();

        expect(repository.current!.appearance.theme, UserSettingsTheme.light);
      },
    );

    test('re-reads the stored blob when Discord rejects the data', () async {
      final transport = _Transport(
        stored: _blob(theme: 1),
        failure: const DiscordApiException(
          statusCode: 400,
          message: 'Invalid settings',
          responsePayload: {'code': 50105},
        ),
      );
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.flush();

      expect(transport.reads, [1]);
      expect(repository.current!.appearance.theme, UserSettingsTheme.dark);
      expect(repository.lastWriteError, isA<DiscordApiException>());
    });

    test('survives a reload that also fails', () async {
      final transport = _Transport(
        readFailure: StateError('offline'),
        failure: const DiscordApiException(
          statusCode: 400,
          message: 'Invalid settings',
          responsePayload: {'code': 50105},
        ),
      );
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.flush();

      expect(repository.lastWriteError, isA<DiscordApiException>());
    });

    test('reports an ordinary failure without re-reading', () async {
      final transport = _Transport(failure: StateError('socket closed'));
      final repository = _loaded(transport);
      addTearDown(repository.close);
      final seen = <UserSettings>[];
      repository.updates.listen(seen.add);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await repository.flush();
      await pumpEventQueue();

      expect(repository.lastWriteError, isA<StateError>());
      expect(transport.reads, isEmpty);
      // The optimistic value and the failure both reach the surface.
      expect(seen, hasLength(2));
    });

    test('serialises a second write behind the one in flight', () async {
      final transport = _Transport(delayWrites: true);
      final repository = _loaded(transport);
      addTearDown(repository.close);

      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      final first = repository.flush();
      // Let the first write reach the transport before the next edit lands,
      // so this exercises queueing rather than coalescing.
      await pumpEventQueue();
      await repository.apply(const UserSettingsPatch(quietMode: true));
      final second = repository.flush();
      transport.release();
      await Future.wait([first, second]);

      expect(transport.writes, hasLength(2));
    });

    test('stops emitting and saving once closed', () async {
      final transport = _Transport();
      final repository = _loaded(transport);
      var updates = 0;
      repository.updates.listen((_) => updates++);

      await repository.close();
      repository.acceptGatewayDispatch('READY', {
        'user_settings_proto': _blob(theme: 2),
      });
      await repository.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );
      await pumpEventQueue();

      expect(updates, 0);
      expect(transport.writes, isEmpty);
    });
  });
}

DiscordUserSettingsRepository _loaded(_Transport transport) {
  final repository = DiscordUserSettingsRepository(transport)
    ..acceptGatewayDispatch('READY', {'user_settings_proto': _blob(theme: 1)});
  return repository;
}

String _blob({int? theme, bool quiet = false}) {
  final root = ProtoMessage();
  if (theme != null) {
    root.setMessage(
      PreloadedUserSettingsField.appearance,
      ProtoMessage()
        ..setVarint(AppearanceField.theme, theme)
        ..setBool(AppearanceField.developerMode, true),
    );
  }
  if (quiet) {
    root.setMessage(
      PreloadedUserSettingsField.notifications,
      ProtoMessage()..setBoolWrapper(NotificationField.quietMode, true),
    );
  }
  return DiscordUserSettingsProto.encodeBase64(root.encode());
}

final class _Transport implements DiscordUserSettingsTransport {
  _Transport({
    this.stored,
    this.response = '',
    this.outOfDate = false,
    this.failure,
    this.readFailure,
    this.delayWrites = false,
  });

  final String? stored;
  final String? response;
  final bool outOfDate;
  final Object? failure;
  final Object? readFailure;
  final bool delayWrites;

  final List<int> reads = [];
  final List<String> writes = [];

  /// Held open until [release], so a test can watch what a second write does
  /// while the first one is still on the wire.
  late final Completer<void>? _gate = delayWrites ? Completer<void>() : null;

  void release() => _gate?.complete();

  @override
  Future<String?> readSettingsProto(int type) async {
    reads.add(type);
    if (readFailure case final error?) throw error;
    return stored;
  }

  @override
  Future<DiscordSettingsWriteResult> writeSettingsProto({
    required int type,
    required String settings,
  }) async {
    writes.add(settings);
    if (_gate case final gate?) await gate.future;
    if (failure case final error?) throw error;
    return DiscordSettingsWriteResult(settings: response, outOfDate: outOfDate);
  }
}
