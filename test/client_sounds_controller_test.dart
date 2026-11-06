import 'package:flucord/src/application/client_sounds_controller.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flucord/src/domain/soundboard_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fetched sound plays from the cache', () async {
    final harness = _Harness()..library.cached[ClientSound.mute] = 'file:///m';

    harness.controller.play(ClientSound.mute);
    await pumpEventQueue();

    expect(harness.player.log, ['play file:///m']);
  });

  test('a missing sound plays its bundled fallback, or nothing', () async {
    final harness = _Harness();

    harness.controller.play(ClientSound.callRinging);
    harness.controller.play(ClientSound.message);
    await pumpEventQueue();

    expect(harness.player.log, ['play asset://assets/sounds/call_ring.wav']);
  });

  test('a player that fails is not an error the person sees', () async {
    final harness = _Harness()..player.fail = true;

    harness.controller.play(ClientSound.userJoin);
    await pumpEventQueue();

    expect(harness.player.log, isEmpty);
  });

  test('a loop repeats until stopped', () async {
    final harness = _Harness()
      ..library.cached[ClientSound.callCalling] = 'file:///c';

    harness.controller.loop(ClientSound.callCalling);
    await pumpEventQueue();
    harness.controller.stopLoop();
    await pumpEventQueue();

    expect(harness.player.log, ['loop file:///c', 'stop']);
  });

  test('the switch silences every sound and is kept', () async {
    final harness = _Harness();
    await harness.controller.load();
    harness.controller.loop(ClientSound.callRinging);
    await pumpEventQueue();

    await harness.controller.setEnabled(enabled: false);
    harness.controller.play(ClientSound.userJoin);
    await pumpEventQueue();

    expect(harness.repository.saved, [false]);
    expect(harness.controller.enabled, isFalse);
    expect(harness.player.log, [
      'loop asset://assets/sounds/call_ring.wav',
      'stop',
    ]);
  });

  test('a stored off switch is read on load', () async {
    final harness = _Harness()..repository.stored = false;

    await harness.controller.load();
    harness.controller.play(ClientSound.userJoin);
    await pumpEventQueue();

    expect(harness.player.log, isEmpty);
  });

  test('streamer mode silences sounds too', () async {
    var silenced = true;
    final harness = _Harness(isSilenced: () => silenced);

    harness.controller.play(ClientSound.userJoin);
    await pumpEventQueue();
    silenced = false;
    harness.controller.play(ClientSound.userJoin);
    await pumpEventQueue();

    expect(harness.player.log, hasLength(1));
  });
}

final class _Harness {
  _Harness({bool Function()? isSilenced}) {
    controller = ClientSoundsController(
      library: library,
      repository: repository,
      playerFactory: () => player,
      isSilenced: isSilenced,
    );
  }

  final library = _FakeLibrary();
  final repository = _FakeRepository();
  final player = _FakePlayer();
  late final ClientSoundsController controller;
}

final class _FakeLibrary implements ClientSoundLibrary {
  final Map<ClientSound, String> cached = {};

  @override
  Future<String?> localUrl(ClientSound sound) async => cached[sound];

  @override
  Future<void> fetchAll() async {}
}

final class _FakeRepository implements ClientSoundSettingsRepository {
  bool stored = true;
  final List<bool> saved = [];

  @override
  Future<bool> loadEnabled() async => stored;

  @override
  Future<void> saveEnabled({required bool enabled}) async => saved.add(enabled);
}

final class _FakePlayer implements SoundboardAudioPlayer {
  bool fail = false;
  final List<String> log = [];

  @override
  Future<void> play(String url, {double volume = 1, bool loop = false}) async {
    if (fail) throw StateError('no audio device');
    log.add('${loop ? 'loop' : 'play'} $url');
  }

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> dispose() async {}
}
