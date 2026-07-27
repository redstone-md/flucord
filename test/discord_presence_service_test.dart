import 'dart:async';

import 'package:flucord/src/data/discord/discord_desktop_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_presence_service.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

part 'discord_presence_service_editing_cases.dart';

const _me = '111111111111111111';
const _mira = '222222222222222222';
const _roman = '333333333333333333';
const _forge = '123456789012345678';
const _atlas = '234567890123456789';

/// A settings store whose writes land immediately, the way the real one's
/// optimistic apply does.
final class _FakeSettings implements UserSettingsRepository {
  _FakeSettings({this.loaded = true});

  final StreamController<UserSettings> _updates = StreamController.broadcast();
  final List<UserSettingsPatch> patches = [];
  bool loaded;
  UserSettings? stored = const UserSettings();

  @override
  Stream<UserSettings> get updates => _updates.stream;

  @override
  UserSettings? get current => stored;

  @override
  bool get isLoaded => loaded;

  @override
  Object? get lastWriteError => null;

  @override
  Future<UserSettings> load() async => stored!;

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {
    patches.add(patch);
  }

  @override
  Future<void> flush() async {}

  void push(UserSettings settings) {
    stored = settings;
    _updates.add(settings);
  }

  Future<void> close() => _updates.close();
}

final class _Harness {
  _Harness({_FakeSettings? settings}) : settings = settings ?? _FakeSettings() {
    service = DiscordPresenceService(
      sendPresence: sent.add,
      isSessionEstablished: () => established,
      settings: this.settings,
      clock: () => now,
      // No periodic timer: the test drives the idle machine itself, and a live
      // one would leak into the next test.
      idlePollInterval: null,
    );
  }

  final _FakeSettings settings;
  final List<Map<String, Object?>> sent = [];

  /// Starts closed, the way a socket does: nothing may go out before READY.
  bool established = false;
  DateTime now = DateTime.utc(2026, 7, 26, 12);

  late final DiscordPresenceService service;

  /// READY as the repository delivers it: the socket is up, the dispatch is
  /// applied, and the updater is told it may commit.
  Map<String, UserPresence> ready([Map<String, Object?>? payload]) {
    established = true;
    final changed = service.accept(
      'READY',
      payload ??
          {
            'user': {'id': _me},
          },
    );
    service.sessionEstablished();
    return changed;
  }

  Future<void> dispose() async {
    await service.close();
    await settings.close();
  }
}

Map<String, Object?> _presence(
  String userId, {
  String status = 'online',
  int processedAt = 0,
  List<Object?> activities = const [],
}) => {
  'user': {'id': userId},
  'status': status,
  'processed_at_timestamp': processedAt,
  'activities': activities,
};

void main() {
  test('READY adopts the account and its other sessions', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    final changed = harness.ready({
      'user': {'id': _me},
      'sessions': [
        {
          'session_id': 'phone',
          'status': 'online',
          'active': true,
          'client_info': {'os': 'android'},
        },
      ],
    });

    expect(changed, isEmpty);
    expect(harness.service.currentUserId, _me);
    expect(harness.service.sessions.single.operatingSystem, 'android');
    expect(harness.sent, hasLength(1));
    expect(harness.sent.single['status'], 'online');
  });

  test('READY_SUPPLEMENTAL attributes merged presences by index', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    final changed = harness.service.accept('READY_SUPPLEMENTAL', {
      'guilds': [
        {'id': _forge},
        {'id': _atlas},
      ],
      'merged_presences': {
        'friends': [_presence(_roman, status: 'idle')],
        'guilds': [
          [_presence(_mira, status: 'dnd', processedAt: 10)],
          [_presence(_mira, status: 'online', processedAt: 5)],
        ],
      },
    });

    expect(changed[_roman]!.status, Presence.idle);
    // The guild entry with the newer stamp wins the collapse.
    expect(changed[_mira]!.status, Presence.doNotDisturb);
  });

  test('READY_SUPPLEMENTAL survives a ragged or absent merge block', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.service.accept('READY_SUPPLEMENTAL', const {}), isEmpty);
    expect(
      harness.service.accept('READY_SUPPLEMENTAL', const {
        'merged_presences': {'guilds': 'not a list'},
        'guilds': 'not a list',
      }),
      isEmpty,
    );
    expect(
      harness.service.accept('READY_SUPPLEMENTAL', {
        'guilds': [
          {'id': _forge},
          {'no': 'id'},
        ],
        'merged_presences': {
          'guilds': [
            [_presence(_mira)],
          ],
        },
      }),
      hasLength(1),
    );
  });

  test('a bare-array PRESENCES_REPLACE resets the friend scope', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    harness.service.accept('PRESENCE_UPDATE', _presence(_mira));
    final changed = harness.service.accept('PRESENCES_REPLACE', {
      DiscordDesktopGatewayDispatch.arrayPayloadKey: [
        _presence(_roman, status: 'idle'),
      ],
    });

    expect(changed[_mira]!.status, Presence.offline);
    expect(changed[_roman]!.status, Presence.idle);
  });

  test('a bare-array SESSIONS_REPLACE swaps the session list', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final published = <SelfPresence>[];
    harness.service.selfPresenceUpdates.listen(published.add);

    final changed = harness.service.accept('SESSIONS_REPLACE', {
      DiscordDesktopGatewayDispatch.arrayPayloadKey: [
        {'session_id': 'desktop', 'active': true},
      ],
    });
    await pumpEventQueue();

    expect(changed, isEmpty);
    expect(harness.service.sessions.single.sessionId, 'desktop');
    expect(published, hasLength(1));
  });

  test(
    'a guild snapshot, member chunk and member list all carry presence',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      expect(
        harness.service.accept('GUILD_CREATE', {
          'id': _forge,
          'presences': [_presence(_mira)],
        })[_mira]!.status,
        Presence.online,
      );
      expect(
        harness.service.accept('GUILD_MEMBERS_CHUNK', {
          'guild_id': _forge,
          'presences': [_presence(_roman, status: 'idle')],
        })[_roman]!.status,
        Presence.idle,
      );
      expect(
        harness.service.accept('GUILD_MEMBER_LIST_UPDATE', {
          'guild_id': _forge,
          'ops': [
            {
              'items': [
                {
                  'member': {
                    'user': {'id': _mira},
                    'presence': {
                      'status': 'dnd',
                      'processed_at_timestamp': 99,
                      'activities': <Object?>[],
                    },
                  },
                },
                {'group': <String, Object?>{}},
                'not an object',
              ],
            },
            {
              'item': {
                'member': {
                  'user': {'id': _roman},
                  'presence': {'status': 'offline'},
                },
              },
            },
            {'item': <String, Object?>{}},
          ],
        })[_mira]!.status,
        Presence.doNotDisturb,
      );
    },
  );

  test('guild-scoped dispatches without an id change nothing', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.service.accept('GUILD_CREATE', const {}), isEmpty);
    expect(harness.service.accept('GUILD_MEMBERS_CHUNK', const {}), isEmpty);
    expect(
      harness.service.accept('GUILD_MEMBER_LIST_UPDATE', const {}),
      isEmpty,
    );
    expect(
      harness.service.accept('GUILD_MEMBER_LIST_UPDATE', const {
        'guild_id': _forge,
        'ops': 'not a list',
      }),
      isEmpty,
    );
    expect(
      harness.service.accept('GUILD_MEMBER_LIST_UPDATE', const {
        'guild_id': _forge,
        'ops': <Object?>[],
      }),
      isEmpty,
    );
    expect(harness.service.accept('GUILD_DELETE', const {}), isEmpty);
    expect(harness.service.accept('GUILD_MEMBER_REMOVE', const {}), isEmpty);
    expect(harness.service.accept('PRESENCE_UPDATE', const {}), isEmpty);
    expect(harness.service.accept('MESSAGE_CREATE', const {}), isEmpty);
  });

  test('leaving a guild and losing a member both clear presence', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.service
      ..accept('GUILD_CREATE', {
        'id': _forge,
        'presences': [_presence(_mira)],
      })
      ..accept('GUILD_CREATE', {
        'id': _atlas,
        'presences': [_presence(_roman)],
      });

    expect(
      harness.service.accept('GUILD_MEMBER_REMOVE', {
        'guild_id': _forge,
        'user': {'id': _mira},
      })[_mira]!.status,
      Presence.offline,
    );
    expect(
      harness.service.accept('GUILD_DELETE', {'id': _atlas})[_roman]!.status,
      Presence.offline,
    );
  });

  test('RESUMED re-asserts the presence already on the wire', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.ready();
    expect(harness.sent, hasLength(1));

    harness.service.accept('RESUMED', const {});

    expect(harness.sent, hasLength(2));
  });

  test('the account never appears in the inbound map', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.ready();

    expect(harness.service.accept('PRESENCE_UPDATE', _presence(_me)), isEmpty);
    expect(harness.service.store.presenceFor(_me), isNull);
  });

  test('a settings revision recomposes and re-sends the presence', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.ready();

    harness.settings.push(
      const UserSettings(
        status: StatusPreferences(
          status: 'dnd',
          customStatusText: 'Heads down',
        ),
        voiceAndVideo: VoiceAndVideoPreferences(afkTimeoutSeconds: 120),
      ),
    );
    await pumpEventQueue();

    expect(harness.service.chosenStatus, Presence.doNotDisturb);
    expect(harness.service.customStatus!.state, 'Heads down');
    expect(harness.sent.last['status'], 'dnd');
    expect(
      (harness.sent.last['activities']! as List).single,
      containsPair('state', 'Heads down'),
    );
    expect(harness.service.selfUserPresence.status, Presence.doNotDisturb);
    expect(
      harness.service.selfUserPresence.clientStatus[ClientPlatform.desktop],
      Presence.doNotDisturb,
    );
  });

  test(
    'going idle promotes the broadcast status without rewriting it',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.ready();

      harness.now = harness.now.add(const Duration(minutes: 11));
      harness.service.evaluateIdle();

      expect(harness.service.selfPresence.status, Presence.idle);
      expect(harness.service.chosenStatus, Presence.online);
      expect(harness.sent.last['status'], 'idle');
      expect(harness.sent.last['afk'], isTrue);
      expect(harness.sent.last['since'], greaterThan(0));

      harness.now = harness.now.add(const Duration(seconds: 1));
      harness.service.markActive();

      expect(harness.service.selfPresence.status, Presence.online);
      expect(harness.sent.last['since'], 0);
    },
  );

  test('an unchanged idle evaluation does not compose a new frame', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.ready();
    final before = harness.sent.length;

    harness.service
      ..evaluateIdle()
      ..markActive();

    expect(harness.sent, hasLength(before));
  });

  _editingCases();

  test(
    'a transport with no settings store still composes a presence',
    () async {
      final service = DiscordPresenceService(
        sendPresence: (_) {},
        isSessionEstablished: () => false,
        idlePollInterval: null,
      );
      addTearDown(service.close);

      expect(service.canEdit, isFalse);
      expect(service.chosenStatus, Presence.online);
      expect(service.customStatus, isNull);
      expect(service.selfPresence.status, Presence.online);
      await service.setStatus(Presence.idle);
      await service.setCustomStatus(text: 'x');
    },
  );

  test('the periodic idle poll is wired by default', () async {
    final service = DiscordPresenceService(
      sendPresence: (_) {},
      isSessionEstablished: () => false,
      idlePollInterval: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.close();

    expect(service.selfPresence.status, Presence.online);
  });
}
