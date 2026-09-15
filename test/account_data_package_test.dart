import 'dart:convert';

import 'package:flucord/src/application/account_data_package_controller.dart';
import 'package:flucord/src/data/discord/discord_account_data_package_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/account_data_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading the standing record', () {
    test('reads the whole record', () {
      final package = DiscordAccountDataPackageRepository.readPackage({
        'harvest_id': '1234',
        'status': 'processing',
        'created_at': '2026-09-01T10:00:00+00:00',
        'started_at': '2026-09-02T10:00:00+00:00',
        'expires_at': '2026-09-20T10:00:00+00:00',
        'progress_percent': 41.2,
        'progress_step': 'collecting messages',
        'error_message': null,
      });

      expect(package!.harvestId, '1234');
      expect(package.status, DataPackageStatus.processing);
      expect(package.createdAt, DateTime.parse('2026-09-01T10:00:00+00:00'));
      expect(package.startedAt, isNotNull);
      expect(package.expiresAt, isNotNull);
      expect(package.completedAt, isNull);
      expect(package.failedAt, isNull);
      expect(package.progressPercent, 41);
      expect(package.progressStep, 'collecting messages');
      expect(package.errorMessage, isNull);
      expect(package.isRunning, isTrue);
    });

    test('a record without an id reads as no record', () {
      expect(
        DiscordAccountDataPackageRepository.readPayload({'status': 'pending'}),
        isNull,
      );
      expect(DiscordAccountDataPackageRepository.readPayload(null), isNull);
      expect(
        DiscordAccountDataPackageRepository.readPayload(<String, Object?>{}),
        isNull,
      );
    });

    test('a status this build does not know reads as pending', () {
      final package = DiscordAccountDataPackageRepository.readPayload({
        'harvest_id': '1234',
        'status': 'some-new-state',
      });

      expect(package!.status, DataPackageStatus.pending);
      expect(package.isRunning, isTrue);
    });

    test('every status it does know is read as it is written', () {
      for (final (wire, expected) in [
        ('pending', DataPackageStatus.pending),
        ('processing', DataPackageStatus.processing),
        ('completed', DataPackageStatus.completed),
        ('failed', DataPackageStatus.failed),
      ]) {
        expect(DataPackageStatus.fromWire(wire), expected, reason: wire);
      }
      expect(DataPackageStatus.fromWire('mystery'), isNull);
      expect(DataPackageStatus.fromWire(null), isNull);
      expect(DataPackageStatus.fromWire(4), isNull);
    });

    test('a failed record says why, when Discord said why', () {
      final package = DiscordAccountDataPackageRepository.readPayload({
        'harvest_id': '1234',
        'status': 'failed',
        'failed_at': '2026-09-03T10:00:00+00:00',
        'error_message': 'it broke',
      });

      expect(package!.status, DataPackageStatus.failed);
      expect(package.isRunning, isFalse);
      expect(package.failedAt, isNotNull);
      expect(package.errorMessage, 'it broke');
    });
  });

  group('the routes', () {
    test('the latest comes from the harvest route', () async {
      final transport = _Transport([
        _response({
          'harvest_id': '1234',
          'status': 'completed',
          'created_at': '2026-09-01T10:00:00+00:00',
        }),
      ]);

      final package = await _repository(transport).loadLatest();

      expect(package!.status, DataPackageStatus.completed);
      expect(
        transport.requests.single.$2.path,
        endsWith('/users/@me/harvest/latest'),
      );
    });

    test('no request ever made reads as no package', () async {
      final transport = _Transport([
        DiscordHttpResponse(statusCode: 200, headers: const {}, body: 'null'),
      ]);

      expect(await _repository(transport).loadLatest(), isNull);
    });

    test('a request starts the collection', () async {
      final transport = _Transport([
        _response({
          'harvest_id': '1234',
          'created_at': '2026-09-01T10:00:00+00:00',
          'status': 'pending',
        }),
      ]);

      final package = await _repository(transport).request();

      expect(package!.status, DataPackageStatus.pending);
      expect(transport.requests.single.$1, 'POST');
      expect(transport.requests.single.$2.path, endsWith('/users/@me/harvest'));
    });

    test('a refusal answers null, not an error', () async {
      for (final status in [400, 403]) {
        final transport = _Transport([_error(status)]);

        expect(
          await _repository(transport).request(),
          isNull,
          reason: '$status',
        );
      }
    });

    test('anything else is still an error', () async {
      final transport = _Transport([_error(500)]);

      await expectLater(
        _repository(transport).request(),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test('says where the latest request stands', () async {
      final repository = _FakeDataPackage()
        ..package = AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.processing,
          createdAt: _epoch,
          progressPercent: 40,
        );
      final controller = AccountDataPackageController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.package!.status, DataPackageStatus.processing);
      expect(controller.package!.isRunning, isTrue);
    });

    test('an account that never asked reads as no package', () async {
      final controller = AccountDataPackageController(() => _FakeDataPackage());
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.package, isNull);
    });

    test('a request starts the collection and shows it standing', () async {
      final repository = _FakeDataPackage();
      final controller = AccountDataPackageController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.request(), isTrue);

      expect(controller.package, isNotNull);
      expect(controller.package!.isRunning, isTrue);
      expect(repository.requested, isTrue);
      expect(controller.wasRefused, isFalse);
    });

    test('a refusal is stated, not read as an outage', () async {
      final controller = AccountDataPackageController(
        () => _FakeDataPackage()..refuse = true,
      );
      addTearDown(controller.dispose);

      expect(await controller.request(), isFalse);

      expect(controller.wasRefused, isTrue);
      expect(controller.error, isNull);
      expect(controller.package, isNull);
    });

    test('a request that could not be sent is an error', () async {
      final controller = AccountDataPackageController(
        () => _FakeDataPackage()..failNextRequest = true,
      );
      addTearDown(controller.dispose);

      expect(await controller.request(), isFalse);

      expect(controller.error, isA<StateError>());
      expect(controller.wasRefused, isFalse);
    });

    test('a read that could not be sent is an error', () async {
      final controller = AccountDataPackageController(
        () => _FakeDataPackage()..failNextLoad = true,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.error, isA<StateError>());
    });

    test('a transport that has no account does nothing', () async {
      final controller = AccountDataPackageController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.request(), isFalse);
      expect(controller.error, isNull);
    });

    test('the standing is read once, and again only when asked', () async {
      final repository = _FakeDataPackage();
      final controller = AccountDataPackageController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();
      repository.package = AccountDataPackage(
        harvestId: '1234',
        status: DataPackageStatus.completed,
        createdAt: _epoch,
      );
      await controller.load();
      // Cached: the standing is only re-read when asked for.
      expect(controller.package, isNull);

      await controller.load(refresh: true);
      expect(controller.package!.status, DataPackageStatus.completed);
    });

    test('disposing stops notifications', () {
      final controller = AccountDataPackageController(_FakeDataPackage.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      controller.request();

      expect(notifications, 0);
    });
  });
}

DiscordAccountDataPackageRepository _repository(_Transport transport) =>
    DiscordAccountDataPackageRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final _epoch = DateTime.utc(2026, 9, 1);

final class _FakeDataPackage implements AccountDataPackageRepository {
  AccountDataPackage? package;
  bool refuse = false;
  bool failNextLoad = false;
  bool failNextRequest = false;
  bool requested = false;

  @override
  Future<AccountDataPackage?> loadLatest() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    return package;
  }

  @override
  Future<AccountDataPackage?> request() async {
    if (failNextRequest) {
      failNextRequest = false;
      throw StateError('request failed');
    }
    requested = true;
    if (refuse) return null;
    return package ??
        AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.pending,
          createdAt: _epoch,
        );
  }
}

DiscordHttpResponse _response(Object payload) => DiscordHttpResponse(
  statusCode: 200,
  headers: const {},
  body: jsonEncode(payload),
);

DiscordHttpResponse _error(int status) => DiscordHttpResponse(
  statusCode: status,
  headers: const {},
  body: jsonEncode({'message': 'Refused'}),
);

final class _Transport implements DiscordHttpTransport {
  _Transport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<(String, Uri)> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add((method, uri));
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
