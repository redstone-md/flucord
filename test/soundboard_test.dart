import 'dart:async';

import 'package:flucord/src/application/account_entitlements_controller.dart';
import 'package:flucord/src/application/soundboard_controller.dart';
import 'package:flucord/src/data/discord/discord_soundboard_service.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model', () {
    test('a default sound belongs to nobody and plays from the CDN', () {
      const fallback = SoundboardSound(id: '1', name: 'quack');
      const owned = SoundboardSound(id: '1', name: 'quack', guildId: 'g');

      expect(fallback.isDefault, isTrue);
      expect(owned.isDefault, isFalse);
      expect(fallback.url, 'https://cdn.discordapp.com/soundboard-sounds/1');
      expect(fallback == const SoundboardSound(id: '1', name: 'quack'), isTrue);
      expect(
        fallback.hashCode,
        const SoundboardSound(id: '1', name: 'quack').hashCode,
      );
      expect(fallback == owned, isFalse);
      expect(fallback == Object(), isFalse);
      expect(fallback.volume, 1);
      expect(fallback.isAvailable, isTrue);
    });
  });

  group('catalogue', () {
    const quack = SoundboardSound(id: '1', name: 'quack');
    const airhorn = SoundboardSound(id: '10', name: 'airhorn', guildId: 'home');
    const drum = SoundboardSound(id: '20', name: 'Drum roll', guildId: 'away');
    const catalogue = SoundboardCatalogue(
      defaults: [quack],
      byGuild: {
        'away': [drum],
        'home': [airhorn],
      },
    );

    String describe(SoundboardSection section) => switch (section) {
      FavoriteSoundsSection() => 'favourites',
      GuildSoundsSection(:final guildId) => guildId,
      DefaultSoundsSection() => 'defaults',
    };

    test('favourites, then this server, the defaults, and the rest', () {
      final sections = catalogue.sections(
        currentGuildId: 'home',
        favoriteIds: const ['20', 'gone'],
      );

      expect(sections.map(describe), [
        'favourites',
        'home',
        'defaults',
        'away',
      ]);
      // A starred sound nobody holds any more is skipped, not drawn blank.
      expect(sections.first.sounds, [drum]);
    });

    test('a DM call has no server of its own to put first', () {
      expect(catalogue.sections().map(describe), ['defaults', 'away', 'home']);
    });

    test('search keeps the names that hold the query, any case', () {
      final sections = catalogue.sections(
        currentGuildId: 'home',
        favoriteIds: const ['1'],
        query: ' DRUM ',
      );

      expect(sections.map(describe), ['away']);
      expect(sections.single.sounds, [drum]);
    });

    test('finds a sound by id in any server', () {
      expect(catalogue.find('20'), drum);
      expect(catalogue.find('1'), quack);
      expect(catalogue.find('99'), isNull);
    });

    test('without Nitro, only this server and the defaults are in reach', () {
      const reach = SoundboardReach(guildId: 'home');

      expect(reach.allows(airhorn), isTrue);
      expect(reach.allows(quack), isTrue);
      expect(reach.allows(drum), isFalse);
    });

    test('Nitro reaches every server, a DM call included', () {
      final everywhere = SoundboardReach(
        everywhere: PremiumTier.nitro.usesSoundboardEverywhere,
      );

      expect(everywhere.allows(drum), isTrue);
      expect(PremiumTier.nitroBoost.usesSoundboardEverywhere, isTrue);
      expect(PremiumTier.nitroBasic.usesSoundboardEverywhere, isFalse);
      expect(PremiumTier.none.usesSoundboardEverywhere, isFalse);
    });
  });

  group('service', () {
    test('reads a server\'s sounds and the shared defaults', () async {
      final transport = _FakeTransport(
        defaults: [
          {'sound_id': 1, 'name': 'quack', 'volume': 1},
        ],
        guildSounds: [
          {
            'sound_id': '10',
            'name': 'airhorn',
            'guild_id': 'guild-1',
            'emoji_name': '📣',
            'emoji_id': '77',
            'volume': 0.5,
            'available': false,
          },
          // No id at all: skipped rather than listed as a blank tile.
          {'name': 'broken'},
        ],
      );
      final service = DiscordSoundboardService(transport);
      addTearDown(service.close);

      final sounds = await service.loadSounds('guild-1');

      // The server's own come first, then the ones everybody has.
      expect(sounds.map((sound) => sound.id), ['10', '1']);
      final own = sounds.first;
      expect(own.name, 'airhorn');
      expect(own.guildId, 'guild-1');
      expect(own.emojiName, '📣');
      expect(own.emojiId, '77');
      expect(own.volume, 0.5);
      expect(own.isAvailable, isFalse);
      // Discord numbers a default sound's id; it is still addressable.
      expect(sounds.last.isDefault, isTrue);

      await service.loadSounds('guild-1');
      // The defaults are read once per session, not per opening.
      expect(transport.defaultReads, 1);
    });

    test('a server the gateway answered for is not read again', () async {
      final transport = _FakeTransport();
      final service = DiscordSoundboardService(transport);
      addTearDown(service.close);
      service.accept('SOUNDBOARD_SOUNDS', const {
        'guild_id': 'guild-1',
        'soundboard_sounds': [
          {'sound_id': '10', 'name': 'airhorn'},
        ],
      });

      final sounds = await service.loadSounds('guild-1');

      expect(sounds.single.name, 'airhorn');
      expect(transport.guildReads, 0);
    });

    test('a DM call reads only the defaults', () async {
      final transport = _FakeTransport(
        defaults: [
          {'sound_id': 1, 'name': 'quack'},
        ],
      );
      final service = DiscordSoundboardService(transport);
      addTearDown(service.close);

      final sounds = await service.loadSounds(null);

      expect(sounds.single.name, 'quack');
      expect(transport.guildReads, 0);
    });

    test('a large account is asked for in frames of a hundred', () {
      final gateway = _FakeGateway();
      final service = DiscordSoundboardService(
        _FakeTransport(),
        gateway: gateway,
      );
      addTearDown(service.close);

      service.accept('READY', {
        'guilds': [
          for (var index = 0; index < 150; index++) {'id': 'guild-$index'},
          {'id': 'guild-down', 'unavailable': true},
        ],
      });

      expect(gateway.requests.map((ids) => ids.length), [100, 50]);
      // A server in an outage is asked for once it comes back.
      expect(
        gateway.requests.expand((ids) => ids),
        isNot(contains('guild-down')),
      );
    });

    test('a guild nobody loaded has no sounds rather than none at all', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);

      expect(service.catalogue.soundsFor('guild-9'), isEmpty);
    });

    test('playing names the source only for a server sound', () async {
      final transport = _FakeTransport();
      final service = DiscordSoundboardService(transport);
      addTearDown(service.close);

      await service.playSound(
        'voice-1',
        const SoundboardSound(
          id: '10',
          name: 'airhorn',
          guildId: 'guild-1',
          emojiId: '55',
        ),
      );
      await service.playSound(
        'voice-1',
        const SoundboardSound(id: '1', name: 'quack'),
      );

      expect(transport.played.first, {
        'channel_id': 'voice-1',
        'sound_id': '10',
        'source_guild_id': 'guild-1',
      });
      expect(transport.played.last['source_guild_id'], isNull);
    });

    test('a created sound is added and an updated one replaced', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);

      service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
        'guild_id': 'guild-1',
        'sound_id': '10',
        'name': 'airhorn',
      });
      service.accept('GUILD_SOUNDBOARD_SOUND_UPDATE', const {
        'guild_id': 'guild-1',
        'sound_id': '10',
        'name': 'louder airhorn',
      });

      final sounds = service.catalogue.soundsFor('guild-1');
      expect(sounds.single.name, 'louder airhorn');
    });

    test('a deleted sound is dropped', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);
      service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
        'guild_id': 'guild-1',
        'sound_id': '10',
        'name': 'airhorn',
      });

      service.accept('GUILD_SOUNDBOARD_SOUND_DELETE', const {
        'guild_id': 'guild-1',
        'sound_id': '10',
      });

      expect(service.catalogue.soundsFor('guild-1'), isEmpty);
      // Deleting from a guild nothing is held for says nothing.
      expect(
        service.accept('GUILD_SOUNDBOARD_SOUND_DELETE', const {
          'guild_id': 'guild-9',
          'sound_id': '1',
        }),
        isNull,
      );
    });

    test('a bulk update replaces the whole set', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);
      service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
        'guild_id': 'guild-1',
        'sound_id': '10',
        'name': 'gone',
      });

      service.accept('GUILD_SOUNDBOARD_SOUNDS_UPDATE', const {
        'guild_id': 'guild-1',
        'soundboard_sounds': [
          {'sound_id': '20', 'name': 'kept'},
        ],
      });

      expect(service.catalogue.soundsFor('guild-1').single.name, 'kept');
    });

    test('an effect somebody sent is reported', () async {
      final service = DiscordSoundboardService(_FakeTransport());
      final seen = <SoundboardPlayback>[];
      final subscription = service.playbacks.listen(seen.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);

      service.accept('VOICE_CHANNEL_EFFECT_SEND', const {
        'channel_id': 'voice-1',
        'user_id': 'someone',
        'guild_id': 'guild-1',
        'sound_id': 10,
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.channelId, 'voice-1');
      expect(seen.single.userId, 'someone');
      // Numbers and strings both appear on this field.
      expect(seen.single.soundId, '10');
      expect(seen.single.guildId, 'guild-1');
    });

    test('an emoji reaction is not a sound', () async {
      final service = DiscordSoundboardService(_FakeTransport());
      final seen = <SoundboardPlayback>[];
      final subscription = service.playbacks.listen(seen.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);

      // The same dispatch carries emoji reactions, which have no sound id.
      expect(
        service.accept('VOICE_CHANNEL_EFFECT_SEND', const {
          'channel_id': 'voice-1',
          'user_id': 'someone',
          'emoji_name': '👋',
        }),
        isNull,
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });

    test('a malformed dispatch changes nothing', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);

      expect(service.accept('MESSAGE_CREATE', const {}), isNull);
      expect(service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {}), isNull);
      expect(
        service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
          'guild_id': 'guild-1',
        }),
        isNull,
      );
      expect(service.accept('GUILD_SOUNDBOARD_SOUND_DELETE', const {}), isNull);
      expect(
        service.accept('GUILD_SOUNDBOARD_SOUNDS_UPDATE', const {}),
        isNull,
      );
      expect(
        service.accept('VOICE_CHANNEL_EFFECT_SEND', const {'user_id': 'a'}),
        isNull,
      );
      expect(
        service.accept('VOICE_CHANNEL_EFFECT_SEND', const {
          'channel_id': 'voice-1',
          'user_id': 'a',
          'sound_id': 1.5,
        }),
        isNull,
      );
    });

    test('closing twice is harmless', () async {
      final service = DiscordSoundboardService(_FakeTransport());

      await service.close();
      await service.close();

      expect(
        service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
          'guild_id': 'guild-1',
          'sound_id': '1',
        }),
        'guild-1',
      );
      service.accept('VOICE_CHANNEL_EFFECT_SEND', const {
        'channel_id': 'c',
        'user_id': 'u',
        'sound_id': '1',
      });
    });
  });

  group('controller', () {
    test('a transport with no soundboard offers nothing', () async {
      final controller = SoundboardController(() => null);
      addTearDown(controller.dispose);

      controller.show('guild-1');
      await controller.load();

      expect(controller.isSupported, isFalse);
      expect(controller.catalogue.byGuild, isEmpty);
      expect(
        await controller.play('c', const SoundboardSound(id: '1', name: 'x')),
        isFalse,
      );
    });

    test('reads a server once and republishes changes', () async {
      final transport = _FakeTransport(
        guildSounds: [
          {'sound_id': '10', 'name': 'airhorn'},
        ],
      );
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      expect(controller.catalogue.soundsFor('guild-1').single.name, 'airhorn');
      expect(controller.isLoading, isFalse);

      controller.show('guild-1');
      controller.show(null);
      expect(controller.isOffered, isFalse);
      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);
      // A server already read is not fetched again on the next opening.
      expect(transport.guildReads, 1);
    });

    test('plays a sound and refuses an unavailable one', () async {
      final transport = _FakeTransport();
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.play(
          'voice-1',
          const SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
        ),
        isTrue,
      );
      expect(
        await controller.play(
          'voice-1',
          const SoundboardSound(id: '11', name: 'locked', isAvailable: false),
        ),
        isFalse,
      );

      expect(transport.played.length, 1);
    });

    test('a rejected play is reported', () async {
      final transport = _FakeTransport(failWrites: true);
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.play('c', const SoundboardSound(id: '1', name: 'x')),
        isFalse,
      );

      expect(controller.error, isNotNull);
      expect(controller.isSending, isFalse);
    });

    test('a failed read is reported and can be retried', () async {
      final transport = _FakeTransport(failReads: true);
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);

      transport.failReads = false;
      await controller.load();
      expect(controller.error, isNull);
    });

    test('a read already in flight is not started twice', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(gate: gate);
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading, isTrue);
      await controller.load();

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(transport.guildReads, 1);
    });

    test('a second play while one is in flight is refused', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(writeGate: gate);
      final service = DiscordSoundboardService(transport);
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      const sound = SoundboardSound(id: '1', name: 'x');
      final first = controller.play('c', sound);
      expect(controller.isSending, isTrue);
      expect(await controller.play('c', sound), isFalse);

      gate.complete();
      expect(await first, isTrue);
    });

    test(
      'any server changing repaints, since the sheet lists them all',
      () async {
        final service = DiscordSoundboardService(_FakeTransport());
        final controller = SoundboardController(() => service);
        addTearDown(controller.dispose);
        addTearDown(service.close);

        var notifications = 0;
        controller.addListener(() => notifications++);
        service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
          'guild_id': 'guild-9',
          'sound_id': '1',
        });
        await Future<void>.delayed(Duration.zero);
        // Nothing is on screen yet, so nothing is redrawn.
        expect(notifications, 0);

        controller.show('guild-1');
        await Future<void>.delayed(Duration.zero);
        notifications = 0;
        service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
          'guild_id': 'guild-9',
          'sound_id': '2',
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifications, 1);
      },
    );

    group('Nitro', () {
      const away = SoundboardSound(id: '20', name: 'drum', guildId: 'guild-2');

      Future<(SoundboardController, _FakeTransport)> controllerWith(
        PremiumTier tier,
      ) async {
        final transport = _FakeTransport(
          defaults: [
            {'sound_id': 1, 'name': 'quack'},
          ],
        );
        final service = DiscordSoundboardService(transport);
        final entitlements = AccountEntitlementsController(
          () => _FakeEntitlements(tier),
        );
        await entitlements.load();
        final controller = SoundboardController(
          () => service,
          entitlements: entitlements,
        );
        addTearDown(controller.dispose);
        addTearDown(entitlements.dispose);
        addTearDown(service.close);
        return (controller, transport);
      }

      test('without it, another server\'s sound is locked', () async {
        final (controller, transport) = await controllerWith(PremiumTier.none);
        controller.show('guild-1');

        expect(controller.isLocked(away), isTrue);
        expect(await controller.play('voice-1', away), isFalse);
        expect(transport.played, isEmpty);
      });

      test(
        'with it, another server\'s sound goes out with its source',
        () async {
          final (controller, transport) = await controllerWith(
            PremiumTier.nitro,
          );
          controller.show('guild-1');

          expect(controller.isLocked(away), isFalse);
          expect(await controller.play('voice-1', away), isTrue);
          expect(transport.played.single['source_guild_id'], 'guild-2');
        },
      );

      test('a DM call offers the soundboard only with it', () async {
        final (free, _) = await controllerWith(PremiumTier.nitroBasic);
        free.showCall();
        expect(free.isOffered, isFalse);

        final (nitro, transport) = await controllerWith(PremiumTier.nitro);
        nitro.showCall();
        await Future<void>.delayed(Duration.zero);

        expect(nitro.isOffered, isTrue);
        // A call has no server: only the defaults are read.
        expect(transport.defaultReads, 1);
        expect(transport.guildReads, 0);
        expect(await nitro.play('dm-1', away), isTrue);
        expect(transport.played.single['channel_id'], 'dm-1');
      });

      test('arriving after the sheet opened repaints it', () async {
        final service = DiscordSoundboardService(_FakeTransport());
        final entitlements = AccountEntitlementsController(
          () => _FakeEntitlements(PremiumTier.nitro),
        );
        final controller = SoundboardController(
          () => service,
          entitlements: entitlements,
        );
        addTearDown(controller.dispose);
        addTearDown(entitlements.dispose);
        addTearDown(service.close);
        controller.showCall();
        expect(controller.isOffered, isFalse);

        await entitlements.load();

        expect(controller.isOffered, isTrue);
      });
    });

    test('swapping the transport forgets what was loaded', () async {
      var service = DiscordSoundboardService(_FakeTransport());
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      final first = service;
      addTearDown(first.close);

      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      final second = _FakeTransport(
        guildSounds: [
          {'sound_id': '99', 'name': 'new session'},
        ],
      );
      service = DiscordSoundboardService(second);
      addTearDown(() => service.close());

      expect(controller.isSupported, isTrue);
      await controller.load();
      // The new session read the server for itself rather than trusting the
      // old one's record of having done it.
      expect(second.guildReads, 1);
      expect(
        controller.catalogue.soundsFor('guild-1').single.name,
        'new session',
      );
    });
  });
}

final class _FakeTransport implements DiscordSoundboardTransport {
  _FakeTransport({
    this.defaults = const [],
    this.guildSounds = const [],
    this.failReads = false,
    this.failWrites = false,
    this.gate,
    this.writeGate,
  });

  final List<Map<String, Object?>> defaults;
  final List<Map<String, Object?>> guildSounds;
  final Completer<void>? gate;
  final Completer<void>? writeGate;
  final List<Map<String, Object?>> played = [];

  bool failReads;
  final bool failWrites;
  int defaultReads = 0;
  int guildReads = 0;

  @override
  Future<List<Map<String, Object?>>> listDefaultSounds() async {
    defaultReads++;
    await gate?.future;
    if (failReads) throw StateError('unreachable');
    return defaults;
  }

  @override
  Future<Map<String, Object?>> listGuildSounds(String guildId) async {
    guildReads++;
    await gate?.future;
    if (failReads) throw StateError('unreachable');
    return {'items': guildSounds};
  }

  @override
  Future<void> sendSoundboardSound(
    String channelId, {
    required String soundId,
    String? sourceGuildId,
  }) async {
    await writeGate?.future;
    if (failWrites) throw StateError('rejected');
    played.add({
      'channel_id': channelId,
      'sound_id': soundId,
      'source_guild_id': sourceGuildId,
    });
  }
}

final class _FakeGateway implements DiscordSoundboardGateway {
  final List<List<String>> requests = [];

  @override
  void requestSoundboardSounds(List<String> guildIds) => requests.add(guildIds);
}

final class _FakeEntitlements implements AccountEntitlementsRepository {
  _FakeEntitlements(this.tier);

  final PremiumTier tier;

  @override
  Future<AccountEntitlements> loadEntitlements() async =>
      AccountEntitlements(premiumTier: tier);
}
