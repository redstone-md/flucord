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
  bool failNext = false;

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
