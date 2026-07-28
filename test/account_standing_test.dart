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
