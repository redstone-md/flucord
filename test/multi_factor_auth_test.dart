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

  group('the security key client data', () {
    test('carries the challenge unchanged, with type and origin around it', () {
      final clientData = SecurityKeyClientData.create(challenge: 'a-challenge');

      expect(clientData.challenge, 'a-challenge');
      expect(clientData.json, contains('"type":"webauthn.create"'));
      expect(clientData.json, contains('"challenge":"a-challenge"'));
      expect(clientData.json, contains('"origin":"https://discord.com"'));
    });

    test('the JSON is base64url without padding', () {
      final clientData = SecurityKeyClientData.create(challenge: 'abc');

      expect(clientData.base64Url, isNotEmpty);
      expect(clientData.base64Url.contains('='), isFalse);
      expect(encodeBase64Url(utf8.encode('a')), 'YQ');
      expect(encodeBase64Url(utf8.encode('bc')), 'YmM');
      expect(
        utf8.decode(base64Url.decode(clientData.base64Url)),
        clientData.json,
      );
    });

    test('two client datas for the same challenge agree', () {
      expect(
        SecurityKeyClientData.create(challenge: 'abc').base64Url,
        SecurityKeyClientData.create(challenge: 'abc').base64Url,
      );
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

    test('the security key rows come from the webauthn route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode([
            {
              'id': 'cred-1',
              'name': 'Hello key',
              'created_at': '2026-09-01T10:00:00+00:00',
            },
            // A row with no id names nothing and can be removed by nothing.
            {'name': 'nameless'},
          ]),
        ),
      ]);

      final keys = await _repository(transport).loadSecurityKeys();

      expect(keys.single.id, 'cred-1');
      expect(keys.single.name, 'Hello key');
      expect(keys.single.createdAt, isNotNull);
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/webauthn/credentials'),
      );
    });

    test('a row with no name is still listed, under plain wording', () {
      final keys = DiscordMfaRepository.readSecurityKeys([
        {'id': 'cred-1'},
      ]);

      expect(keys.single.name, 'Security key');
    });

    test('the challenge is bought with the password', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'challenge': 'a-challenge'}),
        ),
      ]);

      final challenge = await _repository(
        transport,
      ).requestSecurityKeyChallenge('hunter2');

      expect(challenge, 'a-challenge');
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/webauthn/credentials/registration-options'),
      );
      expect(transport.requests.single.body, {'password': 'hunter2'});
    });

    test(
      'a challenge Discord would not buy answers null, not an error',
      () async {
        for (final status in [400, 401]) {
          final transport = _Transport([
            DiscordHttpResponse(
              statusCode: status,
              headers: const {},
              body: jsonEncode({'message': 'Invalid password'}),
            ),
          ]);

          expect(
            await _repository(transport).requestSecurityKeyChallenge('wrong'),
            isNull,
            reason: '$status',
          );
        }

        final empty = _Transport([]);
        expect(
          await _repository(empty).requestSecurityKeyChallenge(''),
          isNull,
        );
        expect(empty.requests, isEmpty);
      },
    );

    test('the registration sends the browser response shape', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'id': 'cred-1'}),
        ),
      ]);
      const registration = SecurityKeyRegistration(
        credentialId: 'cred-1',
        attestationObject: 'attestation',
        clientDataJson: 'client-data',
      );

      final registered = await _repository(transport).registerSecurityKey(
        name: ' Hello key ',
        challenge: 'a-challenge',
        registration: registration,
      );

      expect(registered, isTrue);
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/webauthn/credentials'),
      );
      expect(transport.requests.single.body, {
        'challenge': 'a-challenge',
        'name': 'Hello key',
        'response': {
          'id': 'cred-1',
          'rawId': 'cred-1',
          'type': 'public-key',
          'response': {
            'attestationObject': 'attestation',
            'clientDataJSON': 'client-data',
            'transports': <String>[],
          },
        },
      });
    });

    test('nothing is registered without a name or a challenge', () async {
      const registration = SecurityKeyRegistration(
        credentialId: 'cred-1',
        attestationObject: 'attestation',
        clientDataJson: 'client-data',
      );
      final transport = _Transport([]);
      final repository = _repository(transport);

      expect(
        await repository.registerSecurityKey(
          name: '  ',
          challenge: 'a-challenge',
          registration: registration,
        ),
        isFalse,
      );
      expect(
        await repository.registerSecurityKey(
          name: 'Hello key',
          challenge: '',
          registration: registration,
        ),
        isFalse,
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'a registration Discord refused answers false, not an error',
      () async {
        for (final status in [400, 401]) {
          final transport = _Transport([
            DiscordHttpResponse(
              statusCode: status,
              headers: const {},
              body: jsonEncode({'message': 'Refused'}),
            ),
          ]);

          expect(
            await _repository(transport).registerSecurityKey(
              name: 'Hello key',
              challenge: 'a-challenge',
              registration: const SecurityKeyRegistration(
                credentialId: 'cred-1',
                attestationObject: 'attestation',
                clientDataJson: 'client-data',
              ),
            ),
            isFalse,
            reason: '$status',
          );
        }
      },
    );

    test('removing a key spends the password and names the key', () async {
      final transport = _Transport([
        DiscordHttpResponse(statusCode: 204, headers: const {}, body: ''),
      ]);
      const key = SecurityKey(id: 'cred-1', name: 'Hello key');

      expect(
        await _repository(transport).removeSecurityKey(key, 'hunter2'),
        isTrue,
      );

      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/mfa/webauthn/credentials/cred-1'),
      );
      expect(transport.requests.single.method, 'DELETE');
      expect(transport.requests.single.body, {'password': 'hunter2'});
    });

    test('a removal Discord refused answers false, not an error', () async {
      for (final status in [400, 401]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Refused'}),
          ),
        ]);

        expect(
          await _repository(
            transport,
          ).removeSecurityKey(const SecurityKey(id: 'cred-1'), 'wrong'),
          isFalse,
          reason: '$status',
        );
      }
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

    test('the security key flow states where it is at each step', () async {
      final repository = _FakeMfa();
      final ceremony = _FakeCeremony();
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: ceremony,
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      expect(controller.securityKeyStage, MfaSecurityKeyStage.idle);
      expect(controller.isSecurityKeyCeremonyAvailable, isTrue);

      expect(
        await controller.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'hunter2',
        ),
        isTrue,
      );

      // The password bought the challenge; the ceremony got the account it
      // was asked to act for.
      expect(repository.challengePasswords, ['hunter2']);
      expect(ceremony.asked.single, ('challenge-1', 'user-1', 'Ada'));
      expect(repository.registered.single.$1, 'Hello key');
      expect(controller.securityKeyStage, MfaSecurityKeyStage.added);
      expect(controller.securityKeys.single.name, 'Hello key');
    });

    test('a refused password is named, not read as an outage', () async {
      final repository = _FakeMfa()..acceptPassword = false;
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'wrong',
        ),
        isFalse,
      );

      expect(
        controller.securityKeyRefusal,
        MfaSecurityKeyRefusal.passwordRefused,
      );
      expect(controller.error, isNull);
      expect(controller.securityKeyStage, MfaSecurityKeyStage.idle);
    });

    test('a closed prompt says so and stays ordinary', () async {
      final ceremony = _FakeCeremony()..decline = true;
      final controller = MultiFactorAuthController(
        () => _FakeMfa(),
        securityKeyCeremony: ceremony,
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'hunter2',
        ),
        isFalse,
      );

      expect(controller.securityKeyRefusal, MfaSecurityKeyRefusal.keyDeclined);
      expect(controller.error, isNull);
      expect(controller.securityKeyStage, MfaSecurityKeyStage.idle);
    });

    test(
      'a registration Discord refused is named, not read as an outage',
      () async {
        final repository = _FakeMfa()..acceptRegistration = false;
        final controller = MultiFactorAuthController(
          () => repository,
          securityKeyCeremony: _FakeCeremony(),
          securityKeyAccount: () =>
              const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
        );
        addTearDown(controller.dispose);

        expect(
          await controller.beginSecurityKeyEnrolment(
            name: 'Hello key',
            password: 'hunter2',
          ),
          isFalse,
        );

        expect(
          controller.securityKeyRefusal,
          MfaSecurityKeyRefusal.registrationRefused,
        );
        expect(controller.error, isNull);
      },
    );

    test('a security-key step that could not be sent is an error', () async {
      final controller = MultiFactorAuthController(
        () => _FakeMfa()..failNext = true,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'hunter2',
        ),
        isFalse,
      );

      expect(controller.error, isA<StateError>());
      expect(controller.securityKeyStage, MfaSecurityKeyStage.idle);
    });

    test('no ceremony or no account means no enrolment', () async {
      final repository = _FakeMfa();
      final noCeremony = MultiFactorAuthController(() => repository);
      addTearDown(noCeremony.dispose);
      expect(noCeremony.isSecurityKeyCeremonyAvailable, isFalse);
      expect(
        await noCeremony.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'hunter2',
        ),
        isFalse,
      );

      final noAccount = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
      );
      addTearDown(noAccount.dispose);
      expect(
        await noAccount.beginSecurityKeyEnrolment(
          name: 'Hello key',
          password: 'hunter2',
        ),
        isFalse,
      );
      expect(repository.registered, isEmpty);
    });

    test('a key with no name asks for nothing', () async {
      final repository = _FakeMfa();
      final ceremony = _FakeCeremony();
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: ceremony,
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.beginSecurityKeyEnrolment(name: '  ', password: 'p'),
        isFalse,
      );

      // Nothing was bought and no prompt was shown: the wording of the
      // refusal belongs to the empty field, not to Windows or Discord.
      expect(repository.challengePasswords, isEmpty);
      expect(ceremony.asked, isEmpty);
      expect(repository.registered, isEmpty);
    });

    test('the keys are loaded once, and again only when asked', () async {
      final repository = _FakeMfa()
        ..securityKeys = const [SecurityKey(id: 'cred-1', name: 'Hello key')];
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);

      await controller.loadSecurityKeys();
      expect(controller.securityKeys.single.id, 'cred-1');

      repository.securityKeys = const [SecurityKey(id: 'cred-2')];
      await controller.loadSecurityKeys();
      // Cached: the list is only re-read when asked for.
      expect(controller.securityKeys.single.id, 'cred-1');

      await controller.loadSecurityKeys(refresh: true);
      expect(controller.securityKeys.single.id, 'cred-2');
    });

    test('removing a key takes it off the list', () async {
      final repository = _FakeMfa()
        ..securityKeys = const [SecurityKey(id: 'cred-1', name: 'Hello key')];
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);
      await controller.loadSecurityKeys();

      expect(
        await controller.removeSecurityKey(
          const SecurityKey(id: 'cred-1', name: 'Hello key'),
          'hunter2',
        ),
        isTrue,
      );

      expect(controller.securityKeys, isEmpty);
      expect(repository.removed.single, (
        const SecurityKey(id: 'cred-1', name: 'Hello key'),
        'hunter2',
      ));
    });

    test('a removal Discord refused is named, not read as an outage', () async {
      final repository = _FakeMfa()
        ..securityKeys = const [SecurityKey(id: 'cred-1')]
        ..acceptRemoval = false;
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);
      await controller.loadSecurityKeys();

      expect(
        await controller.removeSecurityKey(
          const SecurityKey(id: 'cred-1'),
          'wrong',
        ),
        isFalse,
      );

      expect(
        controller.securityKeyRefusal,
        MfaSecurityKeyRefusal.removalRefused,
      );
      expect(controller.error, isNull);
      expect(controller.securityKeys, isNotEmpty);
    });

    test('dismissing the added state offers another key', () async {
      final repository = _FakeMfa();
      final controller = MultiFactorAuthController(
        () => repository,
        securityKeyCeremony: _FakeCeremony(),
        securityKeyAccount: () =>
            const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
      );
      addTearDown(controller.dispose);
      await controller.beginSecurityKeyEnrolment(
        name: 'Hello key',
        password: 'hunter2',
      );
      expect(controller.securityKeyStage, MfaSecurityKeyStage.added);

      controller.dismissAddedSecurityKey();

      expect(controller.securityKeyStage, MfaSecurityKeyStage.idle);
      expect(controller.addedSecurityKey, isNull);
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

  List<SecurityKey> securityKeys = const [];
  final List<String> challengePasswords = [];
  final List<(String, String, SecurityKeyRegistration)> registered = [];
  final List<(SecurityKey, String)> removed = [];
  bool acceptPassword = true;
  bool acceptRegistration = true;
  bool acceptRemoval = true;

  @override
  Future<List<SecurityKey>> loadSecurityKeys() async {
    if (failNext) {
      failNext = false;
      throw StateError('load failed');
    }
    return securityKeys;
  }

  @override
  Future<String?> requestSecurityKeyChallenge(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('challenge failed');
    }
    challengePasswords.add(password);
    return acceptPassword ? 'challenge-1' : null;
  }

  @override
  Future<bool> registerSecurityKey({
    required String name,
    required String challenge,
    required SecurityKeyRegistration registration,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('register failed');
    }
    if (!acceptRegistration) return false;
    registered.add((name, challenge, registration));
    securityKeys = [
      ...securityKeys,
      SecurityKey(id: registration.credentialId, name: name),
    ];
    return true;
  }

  @override
  Future<bool> removeSecurityKey(SecurityKey key, String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('remove failed');
    }
    if (!acceptRemoval) return false;
    removed.add((key, password));
    securityKeys = [
      for (final other in securityKeys)
        if (other.id != key.id) other,
    ];
    return true;
  }

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

final class _FakeCeremony implements SecurityKeyCeremony {
  bool decline = false;

  /// Every ceremony the controller asked for, with the challenge and the
  /// account it was given.
  final List<(String, String, String)> asked = [];

  @override
  bool get isAvailable => true;

  @override
  Future<SecurityKeyRegistration?> createCredential({
    required String challenge,
    required SecurityKeyAccount account,
  }) async {
    asked.add((challenge, account.userId, account.displayName));
    if (decline) return null;
    return const SecurityKeyRegistration(
      credentialId: 'cred-1',
      attestationObject: 'attestation',
      clientDataJson: 'client-data',
    );
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
