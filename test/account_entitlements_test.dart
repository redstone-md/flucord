import 'dart:convert';

import 'package:flucord/src/application/account_entitlements_controller.dart';
import 'package:flucord/src/data/discord/discord_account_entitlements_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("the limits the account's tiers grant", () {
    test('the message length doubles only with the full subscription', () {
      expect(PremiumTier.none.messageCharacterLimit, 2000);
      expect(PremiumTier.nitroBasic.messageCharacterLimit, 2000);
      expect(PremiumTier.nitro.messageCharacterLimit, 4000);
      expect(PremiumTier.nitroBoost.messageCharacterLimit, 4000);
    });

    test('the upload limit follows the subscription', () {
      expect(PremiumTier.none.uploadLimitBytes, 20 * 1024 * 1024);
      expect(PremiumTier.nitroBasic.uploadLimitBytes, 50 * 1024 * 1024);
      expect(PremiumTier.nitro.uploadLimitBytes, 500 * 1024 * 1024);
      expect(PremiumTier.nitroBoost.uploadLimitBytes, 500 * 1024 * 1024);
    });

    test('a boosted server raises the limit for everyone in it', () {
      final base = GuildUploadLimits.uploadLimitFor(
        guildTier: 0,
        tier: PremiumTier.none,
      );
      expect(base, 20 * 1024 * 1024);

      // Level 1 boosts buy no upload room.
      expect(
        GuildUploadLimits.uploadLimitFor(guildTier: 1, tier: PremiumTier.none),
        20 * 1024 * 1024,
      );
      expect(
        GuildUploadLimits.uploadLimitFor(guildTier: 2, tier: PremiumTier.none),
        50 * 1024 * 1024,
      );
      expect(
        GuildUploadLimits.uploadLimitFor(guildTier: 3, tier: PremiumTier.none),
        100 * 1024 * 1024,
      );
      // A subscription that already allows more keeps its own room.
      expect(
        GuildUploadLimits.uploadLimitFor(guildTier: 2, tier: PremiumTier.nitro),
        500 * 1024 * 1024,
      );
    });
  });

  group('reading the entitlements payload', () {
    test('a premium subscription names its tier', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '444444444444444444',
              'type': 2,
              'deleted': false,
              'sku_id': '555555555555555555',
              'starts_at': '2026-01-01T00:00:00Z',
              'ends_at': '2026-12-31T00:00:00Z',
              'sku': {
                'id': '555555555555555555',
                'name': 'Nitro',
                'premium': true,
              },
            },
          ]);

      expect(entitlements.premiumTier, PremiumTier.nitro);
      expect(entitlements.boostsHeld, 0);
      expect(entitlements.entitlements.single.label, 'Nitro');
      expect(entitlements.entitlements.single.isBoost, isFalse);
      expect(entitlements.hasNothing, isFalse);
    });

    test('a basic SKU reads as the basic tier, never higher', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '2',
              'type': 2,
              'deleted': false,
              'sku': {'name': 'Nitro Basic', 'premium': true},
            },
          ]);

      expect(entitlements.premiumTier, PremiumTier.nitroBasic);
    });

    test('an unknown premium SKU reads as the base premium tier', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '3',
              'type': 2,
              'deleted': false,
              'sku': {'name': 'Something New', 'premium': true},
            },
          ]);

      expect(entitlements.premiumTier, PremiumTier.nitro);
    });

    test('a non-premium SKU grant is not a tier', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '4',
              'type': 2,
              'deleted': false,
              'sku': {'name': 'Some Other Product', 'premium': false},
            },
          ]);

      expect(entitlements.premiumTier, PremiumTier.nitroBasic);
    });

    test('boosts are counted and listed one by one', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {'id': '5', 'type': 13, 'deleted': false},
            {'id': '6', 'type': 13, 'deleted': false},
          ]);

      expect(entitlements.boostsHeld, 2);
      expect(entitlements.entitlements, hasLength(2));
      expect(entitlements.entitlements.first.label, 'Server Boost');
      expect(entitlements.entitlements.first.isBoost, isTrue);
    });

    test('a deleted grant is not held any more', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {'id': '7', 'type': 13, 'deleted': true},
          ]);

      expect(entitlements.hasNothing, isTrue);
    });

    test('a tier this build does not know is ignored, not guessed', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {'id': '8', 'type': 999, 'deleted': false},
            {'deleted': false},
          ]);

      expect(entitlements.hasNothing, isTrue);
    });

    test('the highest tier wins when several are held', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '9',
              'type': 2,
              'deleted': false,
              'sku': {'name': 'Nitro Basic', 'premium': true},
            },
            {
              'id': '10',
              'type': 2,
              'deleted': false,
              'sku': {'name': 'Nitro', 'premium': true},
            },
          ]);

      expect(entitlements.premiumTier, PremiumTier.nitro);
      expect(entitlements.entitlements, hasLength(2));
    });

    test('a grant with no end date says so in plain words', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {'id': '11', 'type': 13, 'deleted': false},
          ]);

      expect(
        entitlements.entitlements.single.describeExpiry(),
        'Does not expire.',
      );
    });

    test('a grant with an end date names the day', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {
              'id': '12',
              'type': 13,
              'deleted': false,
              'ends_at': '2026-09-30T12:00:00Z',
            },
          ]);

      expect(
        entitlements.entitlements.single.describeExpiry(),
        contains('Held until'),
      );
    });

    test('a grant without its own id falls back to the subscription', () {
      final entitlements =
          DiscordAccountEntitlementsRepository.readEntitlements([
            {'type': 2, 'deleted': false, 'subscription_id': 'sub-1'},
          ]);

      expect(entitlements.entitlements.single.id, 'sub-1');
    });

    test('a premium tier names what it changes', () {
      List<String> perksOf(PremiumTier tier) =>
          AccountEntitlements(premiumTier: tier).premiumPerks;

      expect(perksOf(PremiumTier.none), isEmpty);
      expect(perksOf(PremiumTier.nitroBasic), isNotEmpty);
      expect(perksOf(PremiumTier.nitro), isNotEmpty);
      expect(perksOf(PremiumTier.nitroBoost), isNotEmpty);
    });

    test('the wire value round-trips the premium tier', () {
      expect(PremiumTier.fromWire(1), PremiumTier.nitroBasic);
      expect(PremiumTier.fromWire(2), PremiumTier.nitro);
      expect(PremiumTier.fromWire(3), PremiumTier.nitroBoost);
      expect(PremiumTier.fromWire(0), PremiumTier.none);
      expect(PremiumTier.fromWire('nonsense'), PremiumTier.none);
    });
  });

  group('the route', () {
    test('entitlements come from the account route with their SKU', () async {
      final transport = _Transport([
        _response([
          {
            'id': '1',
            'type': 2,
            'deleted': false,
            'sku': {'name': 'Nitro', 'premium': true},
          },
        ]),
      ]);

      final entitlements = await _repository(transport).loadEntitlements();

      expect(entitlements.premiumTier, PremiumTier.nitro);
      expect(
        transport.requests.single.path,
        endsWith('/users/@me/entitlements'),
      );
      expect(
        transport.requests.single.queryParameters,
        allOf(
          containsPair('with_sku', 'true'),
          containsPair('exclude_ended', 'true'),
        ),
      );
    });
  });

  group('the controller', () {
    test('loads once and again only when asked', () async {
      final repository = _FakeEntitlements();
      final controller = AccountEntitlementsController(() => repository);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();
      await controller.load();
      expect(repository.loads, 1);

      await controller.load(refresh: true);
      expect(repository.loads, 2);
    });

    test('a transport offering none does nothing', () async {
      final controller = AccountEntitlementsController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(controller.entitlements, isNull);
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeEntitlements()..failNextLoad = true;
      final controller = AccountEntitlementsController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());

      await controller.load();
      expect(controller.entitlements!.boostsHeld, 1);
    });

    test('disposing stops notifications', () async {
      final controller = AccountEntitlementsController(_FakeEntitlements.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordAccountEntitlementsRepository _repository(_Transport transport) =>
    DiscordAccountEntitlementsRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

const _held = AccountEntitlements(
  premiumTier: PremiumTier.nitro,
  boostsHeld: 1,
  entitlements: [
    AccountEntitlement(id: '1', label: 'Nitro'),
    AccountEntitlement(id: '2', label: 'Server Boost', isBoost: true),
  ],
);

final class _FakeEntitlements implements AccountEntitlementsRepository {
  int loads = 0;
  bool failNextLoad = false;

  @override
  Future<AccountEntitlements> loadEntitlements() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    loads++;
    return _held;
  }
}

DiscordHttpResponse _response(Object payload) => DiscordHttpResponse(
  statusCode: 200,
  headers: const {},
  body: jsonEncode(payload),
);

final class _Transport implements DiscordHttpTransport {
  _Transport(this._responses);

  final List<DiscordHttpResponse> _responses;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(uri);
    return _responses.removeAt(0);
  }

  final List<Uri> requests = [];

  @override
  void close() {}
}
