import 'dart:convert';

import 'package:flucord/src/application/age_verification_controller.dart';
import 'package:flucord/src/data/discord/discord_age_verification_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/age_verification.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _wallet = AgeVerificationMethod(
  method: 'google_wallet',
  vendor: 'google',
  title: 'Google Wallet',
  description: 'Show a saved ID',
  providedBy: 'Google',
);

void main() {
  group('reading the methods', () {
    test('reads what Discord offers', () {
      final methods = DiscordAgeVerificationRepository.readMethods({
        'methods': [
          {
            'method': 'google_wallet',
            'vendor': 'google',
            'title': 'Google Wallet',
            'description': 'Show a saved ID',
            'provided_by': 'Google',
          },
          // Some builds name the field `type` instead.
          {'type': 'facial_age_estimation', 'vendor': 'incode'},
          'nonsense',
          {'vendor': 'nameless'},
        ],
      });

      expect(methods.map((m) => m.method), [
        'google_wallet',
        'facial_age_estimation',
      ]);
      expect(methods.first, _wallet);
      expect(methods.first.hashCode, _wallet.hashCode);
      expect(methods.first.label, 'Google Wallet');
      // A method Discord sent no title for names itself rather than being
      // given wording invented here.
      expect(methods.last.label, 'facial_age_estimation');
      expect(methods.last.providedBy, isEmpty);
      expect(_wallet == Object(), isFalse);
    });

    test('nonsense reads as no methods', () {
      expect(
        DiscordAgeVerificationRepository.readMethods(const {
          'methods': 'nonsense',
        }),
        isEmpty,
      );
      expect(DiscordAgeVerificationRepository.readMethods(const {}), isEmpty);
    });
  });

  group('the routes', () {
    test('methods come from the age route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'methods': [
              {'method': 'google_wallet'},
            ],
          }),
        ),
      ]);

      final methods = await _repository(transport).loadMethods();

      expect(methods.single.method, 'google_wallet');
      expect(
        transport.requests.single.uri.path,
        endsWith('/age-verification/methods'),
      );
    });

    test('starting names the method and its vendor', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'url': 'https://verify.example.com/session'}),
        ),
      ]);

      final started = await _repository(transport).start(_wallet);

      expect(started!.continueUrl, 'https://verify.example.com/session');
      expect(started.canContinue, isTrue);
      expect(
        transport.requests.single.uri.path,
        endsWith('/age-verification/verify'),
      );
      expect(transport.requests.single.body, {
        'method': 'google_wallet',
        'vendor': 'google',
      });
    });

    test('the other spelling of the link is read too', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'redirect_url': 'https://verify.example.com/two'}),
        ),
      ]);

      expect(
        (await _repository(transport).start(_wallet))!.continueUrl,
        'https://verify.example.com/two',
      );
    });

    test(
      'a start with nowhere to continue says so rather than guessing',
      () async {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: 200,
            headers: const {},
            body: jsonEncode(const <String, Object?>{}),
          ),
        ]);

        final started = await _repository(transport).start(_wallet);

        expect(started!.canContinue, isFalse);
        expect(started.continueUrl, isEmpty);
      },
    );

    test('a method this account may not use is refused, not broken', () async {
      for (final status in [400, 403]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Not eligible'}),
          ),
        ]);

        expect(
          await _repository(transport).start(_wallet),
          isNull,
          reason: '$status',
        );
      }
    });

    test('a method with no name is not started', () async {
      final transport = _Transport([]);

      expect(
        await _repository(
          transport,
        ).start(const AgeVerificationMethod(method: '')),
        isNull,
      );
      expect(transport.requests, isEmpty);
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
        _repository(transport).start(_wallet),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test('loads once and again only when asked', () async {
      final repository = _FakeAgeVerification();
      final launcher = _RecordingLauncher();
      final controller = AgeVerificationController(
        () => repository,
        launcher: launcher,
      );
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();
      await controller.load();
      expect(repository.loads, 1);

      await controller.load(refresh: true);
      expect(repository.loads, 2);
      expect(controller.methods.single, _wallet);
    });

    test('a transport offering none does nothing', () async {
      final controller = AgeVerificationController(
        () => null,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.start(_wallet), isFalse);
      expect(controller.methods, isEmpty);
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeAgeVerification()..failNextLoad = true;
      final controller = AgeVerificationController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());

      await controller.load();
      expect(controller.methods, hasLength(1));
    });

    test('starting opens the vendor page outside the application', () async {
      final repository = _FakeAgeVerification();
      final launcher = _RecordingLauncher();
      final controller = AgeVerificationController(
        () => repository,
        launcher: launcher,
      );
      addTearDown(controller.dispose);

      expect(await controller.start(_wallet), isTrue);

      // The check belongs to the vendor; Flucord does not sit between somebody
      // and their identity document.
      expect(launcher.opened.single.toString(), repository.url);
      expect(controller.refusedMethod, isNull);
    });

    test('a refusal names the method rather than reading as a fault', () async {
      final repository = _FakeAgeVerification()..accept = false;
      final controller = AgeVerificationController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(await controller.start(_wallet), isFalse);

      expect(controller.refusedMethod, _wallet);
      expect(controller.error, isNull);
    });

    test('a method needing a vendor app says which one', () async {
      final repository = _FakeAgeVerification()..url = '';
      final controller = AgeVerificationController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(await controller.start(_wallet), isFalse);

      expect(controller.methodNeedingVendorSurface, _wallet);
      expect(controller.refusedMethod, isNull);
      expect(controller.error, isNull);
    });

    test('a start that could not be sent is an error', () async {
      final repository = _FakeAgeVerification()..failNextStart = true;
      final controller = AgeVerificationController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(await controller.start(_wallet), isFalse);

      expect(controller.error, isA<StateError>());
      expect(controller.isStarting, isFalse);
    });

    test('disposing stops notifications', () async {
      final controller = AgeVerificationController(
        _FakeAgeVerification.new,
        launcher: _RecordingLauncher(),
      );
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordAgeVerificationRepository _repository(_Transport transport) =>
    DiscordAgeVerificationRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final class _FakeAgeVerification implements AgeVerificationRepository {
  int loads = 0;
  bool accept = true;
  bool failNextLoad = false;
  bool failNextStart = false;
  String url = 'https://verify.example.com/session';

  @override
  Future<List<AgeVerificationMethod>> loadMethods() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    loads++;
    return const [_wallet];
  }

  @override
  Future<AgeVerificationStart?> start(AgeVerificationMethod method) async {
    if (failNextStart) {
      failNextStart = false;
      throw StateError('start failed');
    }
    if (!accept) return null;
    return AgeVerificationStart(continueUrl: url);
  }
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
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
