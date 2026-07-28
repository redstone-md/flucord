import 'dart:async';

import 'package:flucord/src/application/soundboard_playback_controller.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/soundboard_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plays a sound sent into the channel this client is in', () async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(
          id: '10',
          name: 'airhorn',
          guildId: 'guild-1',
          volume: 0.5,
        ),
      ],
    );
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '10',
        guildId: 'guild-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.played.single, (
      'https://cdn.discordapp.com/soundboard-sounds/10',
      0.5,
    ));
    expect(controller.lastPlayed?.userId, 'someone');
    expect(controller.error, isNull);
  });

  test('a room this client is not in stays silent', () async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
      ],
    );
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-other',
        userId: 'someone',
        soundId: '10',
        guildId: 'guild-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.played, isEmpty);
    expect(controller.lastPlayed, isNull);
  });

  test('an effect while not in voice at all is ignored', () async {
    final repository = _FakeRepository();
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => null,
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '10',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.played, isEmpty);
  });

  test('a sound this session never listed is recorded, not played', () async {
    final repository = _FakeRepository();
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: 'unknown',
        guildId: 'guild-1',
      ),
    );
    // A default sound names no guild, so there is no catalogue to look in.
    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '10',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.played, isEmpty);
    // The room can still say somebody played something.
    expect(controller.lastPlayed?.soundId, '10');
  });

  test('a player that fails is reported rather than thrown', () async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
      ],
    );
    final player = _FakePlayer(fail: true);
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '10',
        guildId: 'guild-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.error, isNotNull);
  });

  test('a transport with no soundboard subscribes to nothing', () async {
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => null,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);

    // Reconciling repeatedly must not pile up subscriptions either.
    controller
      ..reconcile()
      ..reconcile();

    expect(player.played, isEmpty);
  });

  test('swapping the transport follows the new one', () async {
    var repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'old', guildId: 'guild-1'),
      ],
    );
    final first = repository;
    addTearDown(first.close);
    final player = _FakePlayer();
    final controller = SoundboardPlaybackController(
      repositoryProvider: () => repository,
      connectedChannelId: () => 'voice-1',
      player: player,
    )..reconcile();
    addTearDown(controller.dispose);

    repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '20', name: 'new', guildId: 'guild-1'),
      ],
    );
    addTearDown(() => repository.close());
    controller.reconcile();

    // The old transport is no longer listened to.
    first.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '10',
        guildId: 'guild-1',
      ),
    );
    repository.send(
      const SoundboardPlayback(
        channelId: 'voice-1',
        userId: 'someone',
        soundId: '20',
        guildId: 'guild-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.played.single.$1, endsWith('/20'));
  });

  test('disposing releases the device', () async {
    final repository = _FakeRepository();
    final player = _FakePlayer();
    SoundboardPlaybackController(
        repositoryProvider: () => repository,
        connectedChannelId: () => null,
        player: player,
      )
      ..reconcile()
      ..dispose();
    addTearDown(repository.close);

    await Future<void>.delayed(Duration.zero);
    expect(player.isDisposed, isTrue);
  });
}

final class _FakePlayer implements SoundboardAudioPlayer {
  _FakePlayer({this.fail = false});

  final bool fail;
  final List<(String, double)> played = [];
  bool isDisposed = false;

  @override
  Future<void> play(String url, {double volume = 1}) async {
    if (fail) throw StateError('no audio device');
    played.add((url, volume));
  }

  @override
  Future<void> dispose() async => isDisposed = true;
}

final class _FakeRepository implements SoundboardRepository {
  _FakeRepository({this.sounds = const []});

  final List<SoundboardSound> sounds;
  final StreamController<SoundboardPlayback> _playbacks =
      StreamController.broadcast();

  void send(SoundboardPlayback playback) => _playbacks.add(playback);

  @override
  List<SoundboardSound> soundsFor(String guildId) =>
      sounds.where((sound) => sound.guildId == guildId).toList(growable: false);

  @override
  Stream<String> get updates => const Stream<String>.empty();

  @override
  Stream<SoundboardPlayback> get playbacks => _playbacks.stream;

  @override
  Future<List<SoundboardSound>> loadSounds(String guildId) async => sounds;

  @override
  Future<void> playSound(String channelId, SoundboardSound sound) async {}

  Future<void> close() => _playbacks.close();
}
