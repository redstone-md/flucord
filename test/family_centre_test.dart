import 'dart:convert';

import 'package:flucord/src/application/family_centre_controller.dart';
import 'package:flucord/src/data/discord/discord_family_centre_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _payload({Object? auditLog, Object? linked}) => {
  'age_group': 'TEEN',
  'linked_users':
      linked ??
      [
        {'user_id': 'parent-1'},
        'nonsense',
        {'no': 'id'},
      ],
  'users': [
    {'id': 'parent-1', 'global_name': 'Ada'},
    {'user_id': 'friend-1', 'username': 'mira'},
    {'id': 'nameless-1'},
    'nonsense',
  ],
  'teen_audit_log':
      auditLog ??
      {
        'teen_user_id': 'teen-1',
        'totals': {'messages': 12, 'calls': '3', 'bad': 'not a number'},
        'users': [
          {'id': 'friend-1'},
          'friend-2',
        ],
        'guilds': [
          {'guild_id': 'guild-1'},
        ],
      },
};

void main() {
  group('a linked teen', () {
    test('the restrictions come back as Discord names them', () async {
      final repository = _FakeFamilyCentre()
        ..teenControls['teen-1'] = const TeenControls(
          userId: 'teen-1',
          settings: {'block_dms_from_non_friends': true},
          consents: {'share_activity': false},
        );
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      final controls = await controller.loadTeenControls('teen-1');

      expect(controls!.settings['block_dms_from_non_friends'], isTrue);
      expect(controls.consents['share_activity'], isFalse);
      expect(controller.teenControlsFor('teen-1'), isNotNull);

      // Held per teen: opening the page again spends no second request.
      await controller.loadTeenControls('teen-1');
      expect(repository.teenReads, ['teen-1']);
    });

    test('nothing is asked for a teen nobody named', () async {
      final repository = _FakeFamilyCentre();
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.loadTeenControls(''), isNull);
      expect(repository.teenReads, isEmpty);
    });

    test('a failed read is reported rather than thrown', () async {
      final repository = _FakeFamilyCentre()
        ..teenFailure = StateError('read failed');
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.loadTeenControls('teen-1'), isNull);
      expect(controller.error, isA<StateError>());
    });

    test('with no transport there is nobody to ask', () async {
      final controller = FamilyCentreController(() => null);
      addTearDown(controller.dispose);

      expect(await controller.loadTeenControls('teen-1'), isNull);
    });

    test('both halves are read, and anything not a flag is left out', () {
      final read = DiscordFamilyCentreRepository.readTeenControls('teen-1', {
        'settings': {'block_dms': true, 'nonsense': 'not a flag'},
        'consents': {'share_activity': false},
      });

      expect(read.userId, 'teen-1');
      expect(read.settings, {'block_dms': true});
      expect(read.consents, {'share_activity': false});
      expect(read.isEmpty, isFalse);
    });

    test('a payload with neither half reads as empty', () {
      final read = DiscordFamilyCentreRepository.readTeenControls(
        'teen-1',
        const {'settings': 'not a map'},
      );

      expect(read.isEmpty, isTrue);
    });
  });

  group('reading the family centre', () {
    test('reads who is linked and what was counted', () {
      final family = DiscordFamilyCentreRepository.readFamilyCentre(_payload());

      expect(family.ageGroup, 'TEEN');
      expect(family.linkedUserIds, ['parent-1']);
      expect(family.hasLinkedUsers, isTrue);
      expect(family.nameFor('parent-1'), 'Ada');
      expect(family.nameFor('friend-1'), 'mira');
      // A name Discord did not send falls back to the id, so no row is blank.
      expect(family.nameFor('nameless-1'), 'nameless-1');

      final activity = family.activity!;
      expect(activity.teenUserId, 'teen-1');
      // Counts arrive as numbers and as strings; anything else is not a count.
      expect(activity.totals, {'messages': 12, 'calls': 3});
      expect(activity.totalActions, 15);
      expect(activity.userIds, ['friend-1', 'friend-2']);
      expect(activity.guildIds, ['guild-1']);
      expect(activity.isEmpty, isFalse);
    });

    test('a negative count does not eat the total', () {
      final family = DiscordFamilyCentreRepository.readFamilyCentre(
        _payload(
          auditLog: {
            'teen_user_id': 'teen-1',
            'totals': {'messages': 5, 'broken': -9},
          },
        ),
      );

      expect(family.activity!.totalActions, 5);
    });

    test('an account with nobody linked reports none', () {
      final family = DiscordFamilyCentreRepository.readFamilyCentre(
        _payload(
          linked: const <Object?>[],
          auditLog: const <String, Object?>{},
        ),
      );

      expect(family.hasLinkedUsers, isFalse);
      // An empty summary about nobody is what arrives before a teenager is
      // linked; showing an empty card would suggest the link exists.
      expect(family.activity, isNull);
    });

    test('a summary about somebody with nothing yet is still a summary', () {
      final family = DiscordFamilyCentreRepository.readFamilyCentre(
        _payload(auditLog: {'teen_user_id': 'teen-1'}),
      );

      expect(family.activity?.teenUserId, 'teen-1');
      expect(family.activity?.isEmpty, isTrue);
      expect(family.activity?.totalActions, 0);
    });

    test('nonsense reads as an empty centre rather than throwing', () {
      final family = DiscordFamilyCentreRepository.readFamilyCentre(const {
        'linked_users': 'nonsense',
        'users': 'nonsense',
        'teen_audit_log': 'nonsense',
      });

      expect(family.ageGroup, isEmpty);
      expect(family.linkedUserIds, isEmpty);
      expect(family.userNames, isEmpty);
      expect(family.activity, isNull);
      expect(const FamilyCentre().hasLinkedUsers, isFalse);
      expect(const TeenActivitySummary().isEmpty, isTrue);
    });
  });

  group('the routes', () {
    test('the teen route is read, and a refusal is not an outage', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'settings': {'block_dms': true},
            'consents': {'share_activity': true},
          }),
        ),
      ]);

      final controls = await _repository(transport).loadTeenControls('teen-1');

      expect(controls.settings['block_dms'], isTrue);
      expect(
        transport.requests.single.uri.path,
        endsWith('/family-center/teen-1/settings-and-consents'),
      );

      for (final status in [403, 404]) {
        final refused = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: '{"message": "no"}',
          ),
        ]);
        // A teen can unlink at any moment, and reading a link that has gone
        // is an answer rather than a fault.
        expect(
          (await _repository(refused).loadTeenControls('teen-1')).isEmpty,
          isTrue,
        );
      }

      final broken = _Transport([
        const DiscordHttpResponse(statusCode: 500, headers: {}, body: '{}'),
      ]);
      await expectLater(
        _repository(broken).loadTeenControls('teen-1'),
        throwsA(isA<DiscordApiException>()),
      );

      final untouched = _Transport([]);
      expect(
        (await _repository(untouched).loadTeenControls('')).isEmpty,
        isTrue,
      );
      expect(untouched.requests, isEmpty);
    });


    test('the centre is read from the account route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(_payload()),
        ),
      ]);

      final family = await _repository(transport).loadFamilyCentre();

      expect(family.ageGroup, 'TEEN');
      expect(
        transport.requests.single.uri.path,
        endsWith('/family-center/@me'),
      );
      expect(transport.requests.single.method, 'GET');
    });

    test('a link code is asked for, under either name', () async {
      for (final key in ['code', 'link_code']) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: 200,
            headers: const {},
            body: jsonEncode({key: 'ABC-123'}),
          ),
        ]);

        expect(
          await _repository(transport).requestLinkCode(),
          'ABC-123',
          reason: key,
        );
        expect(
          transport.requests.single.uri.path,
          endsWith('/family-center/@me/link-code'),
        );
        expect(transport.requests.single.method, 'POST');
      }
    });

    test('an account Discord will not issue one for gets an answer', () async {
      for (final status in [400, 403]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Not eligible'}),
          ),
        ]);

        expect(
          await _repository(transport).requestLinkCode(),
          isNull,
          reason: '$status',
        );
      }
    });

    test('anything else is still an error', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 500,
          headers: const {},
          body: jsonEncode({'message': 'Server error'}),
        ),
      ]);

      await expectLater(
        _repository(transport).requestLinkCode(),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test('loads once and again only when asked', () async {
      final repository = _FakeFamilyCentre();
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();
      await controller.load();
      expect(repository.loads, 1);

      await controller.load(refresh: true);
      expect(repository.loads, 2);
      expect(controller.familyCentre?.ageGroup, 'TEEN');
      expect(controller.isLoading, isFalse);
    });

    test('a transport with no family centre does nothing', () async {
      final controller = FamilyCentreController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.requestLinkCode(), isNull);
      expect(controller.familyCentre, isNull);
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeFamilyCentre()..failNextLoad = true;
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());

      await controller.load();
      expect(controller.familyCentre, isNotNull);
    });

    test('a link code is held until the page forgets it', () async {
      final repository = _FakeFamilyCentre();
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.requestLinkCode(), 'ABC-123');
      expect(controller.linkCode, 'ABC-123');
      expect(controller.wasLinkCodeRefused, isFalse);
      expect(controller.isRequestingLinkCode, isFalse);

      // A code lets a parent see this account, so it does not outlive the page.
      controller.forgetLinkCode();
      expect(controller.linkCode, isNull);
      // Forgetting nothing changes nothing.
      controller.forgetLinkCode();
      expect(controller.linkCode, isNull);
    });

    test('a refusal is remembered as an answer', () async {
      final repository = _FakeFamilyCentre()..issueCode = false;
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.requestLinkCode(), isNull);
      expect(controller.wasLinkCodeRefused, isTrue);
      expect(controller.error, isNull);

      controller.forgetLinkCode();
      expect(controller.wasLinkCodeRefused, isFalse);
    });

    test('a code that could not be asked for is an error', () async {
      final repository = _FakeFamilyCentre()..failNextCode = true;
      final controller = FamilyCentreController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.requestLinkCode(), isNull);
      expect(controller.error, isA<StateError>());
    });

    test('disposing stops notifications', () async {
      final controller = FamilyCentreController(_FakeFamilyCentre.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordFamilyCentreRepository _repository(_Transport transport) =>
    DiscordFamilyCentreRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final class _FakeFamilyCentre implements FamilyCentreRepository {
  final Map<String, TeenControls> teenControls = {};
  final List<String> teenReads = [];
  Object? teenFailure;

  @override
  Future<TeenControls> loadTeenControls(String teenId) async {
    teenReads.add(teenId);
    if (teenFailure case final error?) throw error;
    return teenControls[teenId] ?? TeenControls(userId: teenId);
  }

  int loads = 0;
  bool issueCode = true;
  bool failNextLoad = false;
  bool failNextCode = false;

  @override
  Future<FamilyCentre> loadFamilyCentre() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    loads++;
    return const FamilyCentre(ageGroup: 'TEEN');
  }

  @override
  Future<String?> requestLinkCode() async {
    if (failNextCode) {
      failNextCode = false;
      throw StateError('code failed');
    }
    return issueCode ? 'ABC-123' : null;
  }
}

final class _Recorded {
  const _Recorded({required this.method, required this.uri});

  final String method;
  final Uri uri;
}

final class _Transport implements DiscordHttpTransport {
  _Transport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<_Recorded> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_Recorded(method: method, uri: uri));
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
