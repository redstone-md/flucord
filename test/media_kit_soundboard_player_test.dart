import 'package:flucord/src/data/media_kit_soundboard_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('opens no audio device until something is played', () async {
    var built = 0;
    final player = MediaKitSoundboardPlayer(
      playerFactory: () {
        built++;
        return _FakePlayer();
      },
    );

    // A session that never joins voice never needs a device.
    expect(built, 0);

    await player.play('https://cdn/1');
    await player.play('https://cdn/2');

    // And a busy channel reuses the one it opened rather than leaking a
    // native handle per sound.
    expect(built, 1);
  });

  test(
    'scales the volume Discord stores into the one media_kit takes',
    () async {
      late _FakePlayer opened;
      final player = MediaKitSoundboardPlayer(
        playerFactory: () => opened = _FakePlayer(),
      );

      await player.play('https://cdn/1', volume: 0.5);
      expect(opened.volumes.single, 50);
      expect(opened.opened.single, 'https://cdn/1');

      // A malformed value cannot blast the speakers.
      await player.play('https://cdn/2', volume: 9);
      expect(opened.volumes.last, 100);
      await player.play('https://cdn/3', volume: -1);
      expect(opened.volumes.last, 0);
    },
  );

  test('a disposed player plays nothing further', () async {
    late _FakePlayer opened;
    final player = MediaKitSoundboardPlayer(
      playerFactory: () => opened = _FakePlayer(),
    );
    await player.play('https://cdn/1');

    await player.dispose();
    // Disposing twice is what a controller shutdown does when it is retried.
    await player.dispose();
    await player.play('https://cdn/2');

    expect(opened.isDisposed, isTrue);
    expect(opened.opened, ['https://cdn/1']);
  });

  test('disposing before anything played opens nothing', () async {
    var built = 0;
    final player = MediaKitSoundboardPlayer(
      playerFactory: () {
        built++;
        return _FakePlayer();
      },
    );

    await player.dispose();

    expect(built, 0);
  });
}

/// media_kit's `Player` is a concrete class, so the fake extends it and
/// records only the three calls this wrapper makes.
final class _FakePlayer implements Player {
  final List<double> volumes = [];
  final List<String> opened = [];
  bool isDisposed = false;

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (playable is Media) opened.add(playable.uri);
  }

  @override
  Future<void> dispose() async => isDisposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
