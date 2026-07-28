import 'dart:async';

import 'package:flucord/src/application/soundboard_controller.dart';
import 'package:flucord/src/data/discord/discord_soundboard_service.dart';
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

    test('a guild nobody loaded has no sounds rather than none at all', () {
      final service = DiscordSoundboardService(_FakeTransport());
      addTearDown(service.close);

      expect(service.soundsFor('guild-9'), isEmpty);
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
        'emoji_id': '55',
        'emoji_name': null,
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

      final sounds = service.soundsFor('guild-1');
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

      expect(service.soundsFor('guild-1'), isEmpty);
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

      expect(service.soundsFor('guild-1').single.name, 'kept');
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
      expect(controller.sounds, isEmpty);
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

      expect(controller.sounds.single.name, 'airhorn');
      expect(controller.isLoading, isFalse);

      controller.show('guild-1');
      controller.show(null);
      expect(controller.sounds, isEmpty);
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

    test('another server changing does not repaint this one', () async {
      final service = DiscordSoundboardService(_FakeTransport());
      final controller = SoundboardController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('guild-1');
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      controller.addListener(() => notifications++);

      service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
        'guild_id': 'guild-9',
        'sound_id': '1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);

      service.accept('GUILD_SOUNDBOARD_SOUND_CREATE', const {
        'guild_id': 'guild-1',
        'sound_id': '1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
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
      expect(controller.sounds.single.name, 'new session');
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
    String? emojiId,
    String? emojiName,
    String? sourceGuildId,
  }) async {
    await writeGate?.future;
    if (failWrites) throw StateError('rejected');
    played.add({
      'channel_id': channelId,
      'sound_id': soundId,
      'emoji_id': emojiId,
      'emoji_name': emojiName,
      'source_guild_id': sourceGuildId,
    });
  }
}
