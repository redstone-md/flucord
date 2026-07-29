import 'dart:convert';

import 'package:flucord/src/application/account_standing_controller.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/discord/discord_safety_hub_repository.dart';
import 'package:flucord/src/domain/account_standing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _payload({
  Object? classifications,
  Object? guildClassifications,
  Object? appealEligibility,
}) => {
  'username': 'mira',
  'account_standing': '100',
  'is_dsa_eligible': true,
  'is_appeal_eligible': true,
  'classifications':
      classifications ??
      [
        {
          'id': 'record-1',
          'title': 'Harassment',
          'subtitle': 'A message was removed',
        },
        'nonsense',
        {'title': 'no id'},
      ],
  'guild_classifications':
      guildClassifications ??
      [
        {'id': 'record-2', 'title': 'Spam', 'guild_id': 'guild-1'},
        // A guild record with no guild belongs in the account half; keeping
        // it here would file it under a server nobody named.
        {'id': 'record-3', 'title': 'Orphan'},
      ],
  'appeal_eligibility': appealEligibility ?? ['record-1'],
};

void main() {
  group('a suspended account', () {
    test('reads its own route, and the ordinary hub is not asked', () async {
      final repository = _FakeSafetyHub()
        ..suspension = const AccountSuspension(
          isSuspended: true,
          reason: 'Harassment',
          classificationId: 'record-1',
          canRequestReview: true,
        );
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.suspension.isSuspended, isTrue);
      expect(controller.suspension.reason, 'Harassment');
      // The hub is closed to a suspended account: asking would report the
      // suspension as an outage.
      expect(controller.standing, isNull);
    });

    test('an account that is not suspended reads the hub as before', () async {
      final repository = _FakeSafetyHub();
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.suspension.isSuspended, isFalse);
      expect(controller.standing, isNotNull);
    });

    test('the appeal goes to the suspended route', () async {
      final repository = _FakeSafetyHub()
        ..suspension = const AccountSuspension(
          isSuspended: true,
          classificationId: 'record-1',
          canRequestReview: true,
        );
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.requestSuspendedReview(), isTrue);

      expect(repository.suspendedReviews, ['record-1']);
      expect(controller.hasRequestedReview('record-1'), isTrue);
      // Asked twice is not asked twice.
      expect(await controller.requestSuspendedReview(), isFalse);
      expect(repository.suspendedReviews, hasLength(1));
    });

    test('a suspension with no record to appeal offers none', () async {
      final repository = _FakeSafetyHub()
        ..suspension = const AccountSuspension(isSuspended: true);
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.requestSuspendedReview(), isFalse);
      expect(repository.suspendedReviews, isEmpty);
    });


    test('an appeal that could not be sent is reported', () async {
      final repository = _FakeSafetyHub()
        ..suspension = const AccountSuspension(
          isSuspended: true,
          classificationId: 'record-1',
        )
        ..failReview = true;
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.requestSuspendedReview(), isFalse);

      expect(controller.error, isA<StateError>());
    });

    test('with no transport there is nothing to appeal to', () async {
      final controller = AccountStandingController(() => null);
      addTearDown(controller.dispose);

      expect(await controller.requestSuspendedReview(), isFalse);
    });

    test('a refused appeal is an answer, not a failure', () async {
      final repository = _FakeSafetyHub()
        ..suspension = const AccountSuspension(
          isSuspended: true,
          classificationId: 'record-1',
        )
        ..acceptSuspendedReview = false;
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.requestSuspendedReview(), isFalse);

      expect(controller.wasReviewRefused('record-1'), isTrue);
      expect(controller.error, isNull);
    });
  });

  group('what the suspended route says', () {
    test('every field is optional, and an absent end is not today', () {
      final read = DiscordSafetyHubRepository.readSuspension(const {
        'suspended': true,
      });

      expect(read.isSuspended, isTrue);
      expect(read.reason, isEmpty);
      expect(read.endsAt, isNull);
      expect(read.canRequestReview, isFalse);
    });

    test('the alternate spellings Discord uses are all read', () {
      final read = DiscordSafetyHubRepository.readSuspension(const {
        'is_suspended': true,
        'title': 'Spam',
        'id': 'record-9',
        'appeal_eligible': true,
        'expires_at': '2026-08-01T00:00:00Z',
      });

      expect(read.isSuspended, isTrue);
      expect(read.reason, 'Spam');
      expect(read.classificationId, 'record-9');
      expect(read.canRequestReview, isTrue);
      expect(read.endsAt, DateTime.utc(2026, 8));
    });

    test('a payload for an account that is not suspended reads as none', () {
      final read = DiscordSafetyHubRepository.readSuspension(const {});

      expect(read.isSuspended, isFalse);
    });
  });

  group('reading the record', () {
    test('reads what the safety hub says', () {
      final standing = DiscordSafetyHubRepository.readStanding(_payload());

      expect(standing.username, 'mira');
      // Discord sends this as a string on some builds.
      expect(standing.standing, 100);
      expect(standing.isDsaEligible, isTrue);
      expect(standing.isAppealEligible, isTrue);
      expect(standing.isClear, isFalse);
      expect(standing.classifications.map((r) => r.id), [
        'record-1',
        'record-2',
      ]);
      expect(standing.accountRecords.single.id, 'record-1');
      expect(standing.accountRecords.single.title, 'Harassment');
      expect(standing.accountRecords.single.subtitle, 'A message was removed');
      expect(standing.accountRecords.single.appealEligible, isTrue);
      expect(standing.guildRecords.single.id, 'record-2');
      expect(standing.guildRecords.single.guildId, 'guild-1');
      expect(standing.guildRecords.single.isGuild, isTrue);
      // Not named in appeal_eligibility, so not offered.
      expect(standing.guildRecords.single.appealEligible, isFalse);
    });

    test('a record can say for itself that it may be appealed', () {
      final standing = DiscordSafetyHubRepository.readStanding(
        _payload(
          classifications: [
            {'id': 'record-1', 'is_appeal_eligible': true},
          ],
          appealEligibility: const <Object?>[],
        ),
      );

      expect(standing.classifications.first.appealEligible, isTrue);
    });

    test('an account with nothing on record says so', () {
      final standing = DiscordSafetyHubRepository.readStanding(
        _payload(
          classifications: const <Object?>[],
          guildClassifications: const <Object?>[],
        ),
      );

      expect(standing.isClear, isTrue);
      expect(standing.accountRecords, isEmpty);
      expect(standing.guildRecords, isEmpty);
    });

    test('nonsense reads as an empty record rather than throwing', () {
      final standing = DiscordSafetyHubRepository.readStanding(const {
        'classifications': 'nonsense',
        'account_standing': 'not a number',
      });

      expect(standing.username, isEmpty);
      expect(standing.standing, 0);
      expect(standing.isClear, isTrue);
      expect(standing.isDsaEligible, isFalse);
    });

    test('a record compares by what it says', () {
      const record = AccountClassification(id: 'r', title: 't');

      expect(record, const AccountClassification(id: 'r', title: 't'));
      expect(
        record.hashCode,
        const AccountClassification(id: 'r', title: 't').hashCode,
      );
      expect(record == const AccountClassification(id: 'r'), isFalse);
      expect(record == Object(), isFalse);
      expect(const AccountStanding().isClear, isTrue);
    });
  });

  group('the routes', () {
    test('the record is read from the account route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(_payload()),
        ),
      ]);

      final standing = await _repository(transport).loadAccountStanding();

      expect(standing.username, 'mira');
      expect(transport.requests.single.uri.path, endsWith('/safety-hub/@me'));
      expect(transport.requests.single.method, 'GET');
    });


    test('a suspension is read from its own route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'suspended': true,
            'reason': 'Harassment',
            'classification_id': 'record-1',
            'can_request_review': true,
            'ends_at': '2026-08-01T00:00:00Z',
          }),
        ),
      ]);

      final suspension = await _repository(transport).loadSuspension();

      expect(suspension.isSuspended, isTrue);
      expect(suspension.endsAt, DateTime.utc(2026, 8));
      expect(
        transport.requests.single.uri.path,
        endsWith('/safety-hub/suspended/@me'),
      );
    });

    test('a 404 or a 403 means not suspended, not an outage', () async {
      for (final status in [404, 403]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: '{"message": "no"}',
          ),
        ]);

        expect(
          (await _repository(transport).loadSuspension()).isSuspended,
          isFalse,
        );
      }
    });

    test('an appeal goes to the suspended route', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      expect(
        await _repository(transport).requestSuspendedReview('record-1'),
        isTrue,
      );

      expect(
        transport.requests.single.uri.path,
        endsWith('/safety-hub/suspended/request-review/record-1'),
      );
      expect(transport.requests.single.method, 'POST');
    });

    test('an appeal with no record asks nothing', () async {
      final transport = _Transport([]);

      expect(await _repository(transport).requestSuspendedReview(''), isFalse);
      expect(transport.requests, isEmpty);
    });

    test('a refused appeal is an answer; anything else still throws', () async {
      for (final status in [400, 409]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: '{"message": "already appealed"}',
          ),
        ]);
        expect(
          await _repository(transport).requestSuspendedReview('record-1'),
          isFalse,
        );
      }

      final broken = _Transport([
        const DiscordHttpResponse(statusCode: 500, headers: {}, body: '{}'),
      ]);
      await expectLater(
        _repository(broken).requestSuspendedReview('record-1'),
        throwsA(isA<DiscordApiException>()),
      );
      final unreadable = _Transport([
        const DiscordHttpResponse(statusCode: 500, headers: {}, body: '{}'),
      ]);
      await expectLater(
        _repository(unreadable).loadSuspension(),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('a review is asked for by record', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      expect(await _repository(transport).requestReview('record-1'), isTrue);

      expect(
        transport.requests.single.uri.path,
        endsWith('/safety-hub/request-review/record-1'),
      );
      expect(transport.requests.single.method, 'POST');
    });

    test('a review Discord will not run is an answer, not a failure', () async {
      for (final status in [400, 409]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Already appealed'}),
          ),
        ]);

        expect(
          await _repository(transport).requestReview('record-1'),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('anything else is still an error', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 403,
          headers: const {},
          body: jsonEncode({'message': 'Forbidden'}),
        ),
      ]);

      await expectLater(
        _repository(transport).requestReview('record-1'),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('a review of nothing asks nothing', () async {
      final transport = _Transport([]);

      expect(await _repository(transport).requestReview(''), isFalse);
      expect(transport.requests, isEmpty);
    });
  });

  group('the controller', () {
    test('loads once and again only when asked', () async {
      final repository = _FakeSafetyHub();
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();
      await controller.load();

      expect(repository.loads, 1);
      expect(controller.standing?.username, 'mira');
      expect(controller.isLoading, isFalse);

      await controller.load(refresh: true);
      expect(repository.loads, 2);
    });

    test('a transport with no safety hub does nothing', () async {
      final controller = AccountStandingController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.requestReview('record-1'), isFalse);

      expect(controller.standing, isNull);
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeSafetyHub()..failNextLoad = true;
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());
      expect(controller.standing, isNull);

      await controller.load();
      expect(controller.standing?.username, 'mira');
      expect(controller.error, isNull);
    });

    test('a requested review is remembered, and a refused one too', () async {
      final repository = _FakeSafetyHub();
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.requestReview('record-1'), isTrue);
      expect(controller.hasRequestedReview('record-1'), isTrue);
      // Asking twice is not asking again.
      expect(await controller.requestReview('record-1'), isFalse);
      expect(repository.reviews, ['record-1']);

      repository.acceptReviews = false;
      expect(await controller.requestReview('record-2'), isFalse);
      expect(controller.wasReviewRefused('record-2'), isTrue);
      expect(controller.hasRequestedReview('record-2'), isFalse);
      // A refusal is an answer, so nothing is reported as broken.
      expect(controller.error, isNull);

      expect(await controller.requestReview(''), isFalse);
    });

    test('a review that could not be sent is an error', () async {
      final repository = _FakeSafetyHub()..failNextReview = true;
      final controller = AccountStandingController(() => repository);
      addTearDown(controller.dispose);

      expect(await controller.requestReview('record-1'), isFalse);

      expect(controller.error, isA<StateError>());
    });

    test('disposing stops notifications', () async {
      final controller = AccountStandingController(_FakeSafetyHub.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordSafetyHubRepository _repository(_Transport transport) =>
    DiscordSafetyHubRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final class _FakeSafetyHub implements SafetyHubRepository {
  AccountSuspension suspension = AccountSuspension.none;
  final List<String> suspendedReviews = [];
  bool acceptSuspendedReview = true;

  @override
  Future<AccountSuspension> loadSuspension() async => suspension;

  bool failReview = false;

  @override
  Future<bool> requestSuspendedReview(String classificationId) async {
    if (failReview) throw StateError('appeal failed');
    suspendedReviews.add(classificationId);
    return acceptSuspendedReview;
  }

  int loads = 0;
  final List<String> reviews = [];
  bool acceptReviews = true;
  bool failNextLoad = false;
  bool failNextReview = false;

  @override
  Future<AccountStanding> loadAccountStanding() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    loads++;
    return const AccountStanding(username: 'mira');
  }

  @override
  Future<bool> requestReview(String classificationId) async {
    if (failNextReview) {
      failNextReview = false;
      throw StateError('review failed');
    }
    if (!acceptReviews) return false;
    reviews.add(classificationId);
    return true;
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
