import 'dart:convert';
import 'dart:math';

import 'package:flucord/src/application/multi_factor_auth_controller.dart';
import 'package:flucord/src/data/discord/discord_mfa_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the secret', () {
    test('is twenty random bytes, written as base32', () {
      final secret = TotpSecret.generate(random: Random(7));

      // Twenty bytes is 160 bits, which is 32 base32 characters.
      expect(secret.value, hasLength(32));
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret.value), isTrue);
      expect(decodeBase32(secret.value), hasLength(20));
    });

    test('two secrets are not the same secret', () {
      // The whole point of a credential is that the next one is different.
      final first = TotpSecret.generate();
      final second = TotpSecret.generate();

      expect(first.value, isNot(second.value));
    });

    test('reads back in fours, the way it is typed by hand', () {
      const secret = TotpSecret('ABCDEFGH');

      expect(secret.readable, 'abcd efgh');
      expect(const TotpSecret('ABCDEF').readable, 'abcd ef');
      expect(const TotpSecret('').readable, isEmpty);
    });

    test('however it was spaced, it means the same secret', () {
      expect(TotpSecret.parse('abcd efgh').value, 'ABCDEFGH');
      expect(TotpSecret.parse('ABCD-EFGH').value, 'ABCDEFGH');
      expect(TotpSecret.parse('abcd.efgh_ijkl').value, 'ABCDEFGHIJKL');
      expect(TotpSecret.parse('abcd efgh'), const TotpSecret('ABCDEFGH'));
      expect(
        TotpSecret.parse('abcd efgh').hashCode,
        const TotpSecret('ABCDEFGH').hashCode,
      );
      expect(const TotpSecret('A') == Object(), isFalse);
    });

    test('the provisioning URI names the account and the issuer', () {
      final uri = Uri.parse(
        const TotpSecret('ABCDEFGH').provisioningUri(account: 'mira chen'),
      );

      expect(uri.scheme, 'otpauth');
      expect(uri.host, 'totp');
      expect(uri.path, '/Discord:mira%20chen');
      expect(uri.queryParameters['secret'], 'ABCDEFGH');
      expect(uri.queryParameters['issuer'], 'Discord');
    });
  });

  group('the routes', () {
    test('enabling sends the secret with the code that proved it', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'token': 'reissued',
            'backup_codes': [
              'aaaa-bbbb',
              {'code': 'cccc-dddd', 'consumed': false},
              {'code': 'eeee-ffff', 'consumed': true},
              {'no': 'code'},
            ],
          }),
        ),
      ]);

      final enrolment = await _repository(
        transport,
      ).enableTotp(secret: const TotpSecret('ABCDEFGH'), code: ' 123456 ');

      expect(enrolment!.token, 'reissued');
      // A spent code is dropped: offering it would offer a way in that is
      // already used up.
      expect(enrolment.backupCodes, ['aaaa-bbbb', 'cccc-dddd']);
      expect(enrolment.hasBackupCodes, isTrue);
      final request = transport.requests.single;
      expect(request.uri.path, endsWith('/users/@me/mfa/totp/enable'));
      expect(request.body, {'code': '123456', 'secret': 'ABCDEFGH'});
    });

    test('a code Discord refused is an answer, not a failure', () async {
      for (final status in [400, 401]) {
        // One refusal for the enable, one for the disable.
        final transport = _Transport([
          for (var i = 0; i < 2; i++)
            DiscordHttpResponse(
              statusCode: status,
              headers: const {},
              body: jsonEncode({'message': 'Invalid two-factor code'}),
            ),
        ]);

        expect(
          await _repository(
            transport,
          ).enableTotp(secret: const TotpSecret('ABCDEFGH'), code: '000000'),
          isNull,
          reason: '$status',
        );
        expect(
          await _repository(transport).disableTotp('000000'),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('nothing is sent without a code or a secret', () async {
      final transport = _Transport([]);
      final repository = _repository(transport);

      expect(
        await repository.enableTotp(
          secret: const TotpSecret('ABCDEFGH'),
          code: '  ',
        ),
        isNull,
      );
      expect(
        await repository.enableTotp(
          secret: const TotpSecret(''),
          code: '123456',
        ),
        isNull,
      );
      expect(await repository.disableTotp('  '), isFalse);
      expect(transport.requests, isEmpty);
    });

    test('disabling sends the current code', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'token': 'reissued'}),
        ),
      ]);

      expect(await _repository(transport).disableTotp('123456'), isTrue);

      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/totp/disable'),
      );
      expect(transport.requests.single.body, {'code': '123456'});
    });

    test('anything else is still an error', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 500,
          headers: const {},
          body: jsonEncode({'message': 'Server error'}),
        ),
        DiscordHttpResponse(
          statusCode: 500,
          headers: const {},
          body: jsonEncode({'message': 'Server error'}),
        ),
      ]);
      final repository = _repository(transport);

      await expectLater(
        repository.enableTotp(
          secret: const TotpSecret('ABCDEFGH'),
          code: '123456',
        ),
        throwsA(isA<DiscordApiException>()),
      );
      await expectLater(
        repository.disableTotp('123456'),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('text-message codes reach their own routes', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(const <String, Object?>{}),
        ),
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(const <String, Object?>{}),
        ),
      ]);
      final repository = _repository(transport);

      expect(await repository.enableSms(), isTrue);
      expect(await repository.disableSms('hunter2'), isTrue);

      expect(
        transport.requests.first.uri.path,
        endsWith('/users/@me/mfa/sms/enable'),
      );
      expect(transport.requests.first.body, isNull);
      expect(
        transport.requests.last.uri.path,
        endsWith('/users/@me/mfa/sms/disable'),
      );
      expect(transport.requests.last.body, {'password': 'hunter2'});
    });

    test('text codes refused by Discord answer rather than throw', () async {
      final transport = _Transport([
        for (var i = 0; i < 2; i++)
          DiscordHttpResponse(
            statusCode: 400,
            headers: const {},
            body: jsonEncode({'message': 'No phone number'}),
          ),
      ]);
      final repository = _repository(transport);

      expect(await repository.enableSms(), isFalse);
      expect(await repository.disableSms('hunter2'), isFalse);
      expect(await repository.disableSms(''), isFalse);
    });

    test('the challenge buys a pair of nonces', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'nonce': 'view-1', 'regenerate_nonce': 'regen-1'}),
        ),
      ]);

      final nonces = await _repository(
        transport,
      ).requestBackupCodeChallenge('hunter2');

      expect(nonces!.view, 'view-1');
      expect(nonces.regenerate, 'regen-1');
      expect(nonces.forRequest(regenerating: false), 'view-1');
      expect(nonces.forRequest(regenerating: true), 'regen-1');
      expect(
        transport.requests.single.uri.path,
        endsWith('/auth/verify/view-backup-codes-challenge'),
      );
      expect(transport.requests.single.body, {'password': 'hunter2'});
    });

    test('a challenge Discord would not answer gives no nonces', () async {
      final refused = _Transport([
        DiscordHttpResponse(
          statusCode: 401,
          headers: const {},
          body: jsonEncode({'message': 'Wrong password'}),
        ),
      ]);
      expect(
        await _repository(refused).requestBackupCodeChallenge('wrong'),
        isNull,
      );

      // A challenge that answered with nothing usable is the same as none.
      final empty = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(const <String, Object?>{}),
        ),
      ]);
      expect(
        await _repository(empty).requestBackupCodeChallenge('hunter2'),
        isNull,
      );

      final blank = _Transport([]);
      expect(await _repository(blank).requestBackupCodeChallenge(''), isNull);
      expect(blank.requests, isEmpty);
    });

    test('reading the codes spends the nonce the request is for', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'backup_codes': ['aaaa-bbbb'],
          }),
        ),
      ]);

      final codes = await _repository(transport).viewBackupCodes(
        key: ' 123456 ',
        nonces: const BackupCodeNonces(view: 'view-1', regenerate: 'regen-1'),
        regenerate: true,
      );

      expect(codes, ['aaaa-bbbb']);
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/codes-verification'),
      );
      expect(transport.requests.single.body, {
        'key': '123456',
        'nonce': 'regen-1',
        'regenerate': true,
      });
    });

    test('no key and no nonce means no request', () async {
      final transport = _Transport([]);
      final repository = _repository(transport);

      expect(
        await repository.viewBackupCodes(
          key: '  ',
          nonces: const BackupCodeNonces(view: 'view-1'),
        ),
        isNull,
      );
      expect(
        await repository.viewBackupCodes(
          key: '123456',
          nonces: const BackupCodeNonces(),
        ),
        isNull,
      );
      expect(const BackupCodeNonces().isEmpty, isTrue);
      expect(transport.requests, isEmpty);
    });

    test('a refused key answers rather than throwing', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 400,
          headers: const {},
          body: jsonEncode({'message': 'Invalid code'}),
        ),
      ]);

      expect(
        await _repository(transport).viewBackupCodes(
          key: '000000',
          nonces: const BackupCodeNonces(view: 'view-1'),
        ),
        isNull,
      );
    });

    test('anything else on the new routes is still an error', () async {
      DiscordHttpResponse serverError() => DiscordHttpResponse(
        statusCode: 500,
        headers: const {},
        body: jsonEncode({'message': 'Server error'}),
      );
      final transport = _Transport([
        serverError(),
        serverError(),
        serverError(),
        serverError(),
      ]);
      final repository = _repository(transport);

      await expectLater(
        repository.enableSms(),
        throwsA(isA<DiscordApiException>()),
      );
      await expectLater(
        repository.disableSms('hunter2'),
        throwsA(isA<DiscordApiException>()),
      );
      await expectLater(
        repository.requestBackupCodeChallenge('hunter2'),
        throwsA(isA<DiscordApiException>()),
      );
      await expectLater(
        repository.viewBackupCodes(
          key: '123456',
          nonces: const BackupCodeNonces(view: 'view-1'),
        ),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('a response carrying no codes is still an enrolment', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'backup_codes': 'nonsense'}),
        ),
      ]);

      final enrolment = await _repository(
        transport,
      ).enableTotp(secret: const TotpSecret('ABCDEFGH'), code: '123456');

      expect(enrolment!.hasBackupCodes, isFalse);
      expect(enrolment.token, isEmpty);
    });
  });

  group('the controller', () {
    test('mints one secret and will not swap it out', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      expect(controller.stage, MfaEnrolmentStage.idle);

      controller.beginEnrolment();
      final secret = controller.secret;
      expect(secret, isNotNull);
      expect(controller.stage, MfaEnrolmentStage.awaitingCode);

      // A second tap must not replace the secret the app was just given.
      controller.beginEnrolment();
      expect(controller.secret, secret);
    });

    test('a transport that cannot set it does nothing', () async {
      final controller = MultiFactorAuthController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      controller.beginEnrolment();
      expect(controller.stage, MfaEnrolmentStage.idle);
      expect(await controller.confirmEnrolment('123456'), isFalse);
      expect(await controller.disable('123456'), isFalse);
    });

    test('the secret is forgotten once the code worked', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);
      controller.beginEnrolment();

      expect(await controller.confirmEnrolment('123456'), isTrue);

      expect(controller.stage, MfaEnrolmentStage.enrolled);
      // It has done its job; from here the authenticator holds it.
      expect(controller.secret, isNull);
      expect(controller.backupCodes, ['aaaa-bbbb']);
      expect(repository.enabled.single.$2, '123456');
    });

    test('a refused code keeps the secret so it can be retried', () async {
      final repository = _FakeMfa()..acceptCode = false;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);
      controller.beginEnrolment();
      final secret = controller.secret;

      expect(await controller.confirmEnrolment('000000'), isFalse);

      expect(controller.wasCodeRefused, isTrue);
      expect(controller.stage, MfaEnrolmentStage.awaitingCode);
      expect(controller.secret, secret);
      expect(controller.error, isNull);
    });

    test('confirming with no secret asks nothing', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.confirmEnrolment('123456'), isFalse);
      expect(repository.enabled, isEmpty);
    });

    test('a failure is reported and changes nothing', () async {
      final repository = _FakeMfa()..failNext = true;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);
      controller.beginEnrolment();

      expect(await controller.confirmEnrolment('123456'), isFalse);

      expect(controller.error, isA<StateError>());
      expect(controller.stage, MfaEnrolmentStage.awaitingCode);
    });

    test('switching it off clears everything it was holding', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);
      controller.beginEnrolment();
      await controller.confirmEnrolment('123456');

      expect(await controller.disable('654321'), isTrue);

      expect(controller.stage, MfaEnrolmentStage.idle);
      expect(controller.backupCodes, isEmpty);
      expect(repository.disabled, ['654321']);
    });

    test('a refused disable leaves the account as it was', () async {
      final repository = _FakeMfa()..acceptCode = false;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.disable('000000'), isFalse);

      expect(controller.wasCodeRefused, isTrue);
      expect(controller.error, isNull);
    });

    test('a disable that could not be sent is an error', () async {
      final repository = _FakeMfa()..failNext = true;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.disable('123456'), isFalse);

      expect(controller.error, isA<StateError>());
    });

    test('text-message codes are switched on and off', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.enableSms(), isTrue);
      expect(repository.smsEnabled, isTrue);

      expect(await controller.disableSms('hunter2'), isTrue);
      expect(repository.smsEnabled, isFalse);
      // The password reached the one request that needs it and nothing else.
      expect(repository.passwords, ['hunter2']);
    });

    test('an account Discord refuses text codes for is told', () async {
      final repository = _FakeMfa()..acceptCode = false;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.enableSms(), isFalse);
      expect(controller.wasCodeRefused, isTrue);
      expect(controller.error, isNull);
    });

    test('a text-code request that failed is an error', () async {
      final repository = _FakeMfa()..failNext = true;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.enableSms(), isFalse);
      expect(controller.error, isA<StateError>());
    });

    test('backup codes are read again, and minted again', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.revealBackupCodes(password: 'hunter2', code: '123456'),
        isTrue,
      );

      expect(controller.backupCodes, ['aaaa-bbbb']);
      // The password bought the nonce; the authenticator code spent it.
      expect(repository.viewed.single, ('123456', 'view-1', false));

      expect(
        await controller.revealBackupCodes(
          password: 'hunter2',
          code: '123456',
          regenerate: true,
        ),
        isTrue,
      );
      expect(controller.backupCodes, ['cccc-dddd']);
      expect(repository.viewed.last, ('123456', 'regen-1', true));
    });

    test('a wrong password or code answers rather than fails', () async {
      final repository = _FakeMfa()..acceptCode = false;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.revealBackupCodes(password: 'wrong', code: '000000'),
        isFalse,
      );

      expect(controller.wasCodeRefused, isTrue);
      expect(controller.error, isNull);
      expect(controller.backupCodes, isEmpty);
    });

    test(
      'a good password with a bad code refuses at the second step',
      () async {
        // The challenge succeeds and the nonce is spent on a code Discord will
        // not take: a different path from the password being wrong.
        final repository = _FakeMfa()..acceptKey = false;
        final controller = MultiFactorAuthController(() => repository);
        addTearDown(controller.dispose);

        expect(
          await controller.revealBackupCodes(
            password: 'hunter2',
            code: '000000',
          ),
          isFalse,
        );

        expect(controller.wasCodeRefused, isTrue);
        expect(controller.error, isNull);
        expect(controller.backupCodes, isEmpty);
        expect(repository.passwords, ['hunter2']);
      },
    );

    test('a reveal that could not be sent is an error', () async {
      final repository = _FakeMfa()..failNext = true;
      final controller = MultiFactorAuthController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.revealBackupCodes(password: 'hunter2', code: '123456'),
        isFalse,
      );

      expect(controller.error, isA<StateError>());
    });

    test('none of it runs without a transport', () async {
      final controller = MultiFactorAuthController(() => null);
      addTearDown(controller.dispose);

      expect(await controller.enableSms(), isFalse);
      expect(await controller.disableSms('hunter2'), isFalse);
      expect(
        await controller.revealBackupCodes(password: 'p', code: '123456'),
        isFalse,
      );
    });

    test('resetting an idle controller changes nothing', () {
      final controller = MultiFactorAuthController(_FakeMfa.new);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.reset();

      expect(notifications, 0);
    });

    test('disposing stops notifications', () {
      final controller = MultiFactorAuthController(_FakeMfa.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      controller.beginEnrolment();

      expect(notifications, 0);
    });
  });
}

DiscordMfaRepository _repository(_Transport transport) => DiscordMfaRepository(
  DiscordRestClient(
    authorization: DiscordDesktopAuthorization('token'),
    transport: transport,
    baseUri: Uri.parse('https://discord.com/api/v9'),
  ),
);

final class _FakeMfa implements MultiFactorAuthRepository {
  final List<(TotpSecret, String)> enabled = [];
  final List<String> disabled = [];
  bool acceptCode = true;

  /// Whether the authenticator code is taken, separately from whether the
  /// password is: the reveal asks two questions and either can be answered no.
  bool acceptKey = true;
  bool failNext = false;
  bool smsEnabled = false;
  final List<String> passwords = [];
  final List<(String, String, bool)> viewed = [];

  @override
  Future<MfaEnrolment?> enableTotp({
    required TotpSecret secret,
    required String code,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('enable failed');
    }
    if (!acceptCode) return null;
    enabled.add((secret, code));
    return const MfaEnrolment(token: 'reissued', backupCodes: ['aaaa-bbbb']);
  }

  @override
  Future<bool> disableTotp(String code) async {
    if (failNext) {
      failNext = false;
      throw StateError('disable failed');
    }
    if (!acceptCode) return false;
    disabled.add(code);
    return true;
  }

  @override
  Future<bool> enableSms() async {
    if (failNext) {
      failNext = false;
      throw StateError('sms failed');
    }
    if (!acceptCode) return false;
    smsEnabled = true;
    return true;
  }

  @override
  Future<bool> disableSms(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('sms failed');
    }
    if (!acceptCode) return false;
    passwords.add(password);
    smsEnabled = false;
    return true;
  }

  @override
  Future<BackupCodeNonces?> requestBackupCodeChallenge(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('challenge failed');
    }
    if (!acceptCode) return null;
    passwords.add(password);
    return const BackupCodeNonces(view: 'view-1', regenerate: 'regen-1');
  }

  @override
  Future<List<String>?> viewBackupCodes({
    required String key,
    required BackupCodeNonces nonces,
    bool regenerate = false,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('view failed');
    }
    if (!acceptCode || !acceptKey) return null;
    viewed.add((key, nonces.forRequest(regenerating: regenerate), regenerate));
    return regenerate ? const ['cccc-dddd'] : const ['aaaa-bbbb'];
  }
}

final class _Recorded {
  const _Recorded({required this.method, required this.uri, this.body});

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
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
    requests.add(
      _Recorded(
        method: method,
        uri: uri,
        body: body == null
            ? null
            : jsonDecode(utf8.decode(body)) as Map<String, Object?>,
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
