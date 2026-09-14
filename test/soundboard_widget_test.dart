import 'dart:async';

import 'package:flucord/src/application/soundboard_controller.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/presentation/widgets/soundboard_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, SoundboardController controller) =>
      tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => SoundboardButton(
                controller: controller,
                channelId: 'voice-1',
              ),
            ),
          ),
        ),
      );

  testWidgets('a transport with no soundboard shows no button', (tester) async {
    final controller = SoundboardController(() => null);
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('soundboard-open')), findsNothing);
  });

  testWidgets('no button outside a server voice channel', (tester) async {
    final repository = _FakeRepository();
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('soundboard-open')), findsNothing);
  });

  testWidgets('plays a sound from the sheet', (tester) async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
        SoundboardSound(id: '1', name: 'quack'),
      ],
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();

    expect(controller.guildId, 'guild-1');
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    expect(find.text('airhorn'), findsOne);
    await tester.tap(find.byKey(const ValueKey('soundboard-sound-10')));
    await tester.pumpAndSettle();

    expect(repository.played.single.id, '10');
  });

  testWidgets('an unavailable sound cannot be played', (tester) async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(
          id: '11',
          name: 'locked',
          guildId: 'guild-1',
          isAvailable: false,
        ),
      ],
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('soundboard-sound-11')));
    await tester.pumpAndSettle();

    expect(repository.played, isEmpty);
  });

  testWidgets('a server with no sounds says so and offers a retry', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('soundboard-empty')), findsOne);
    expect(find.text('This server has no sounds yet.'), findsOne);

    repository.sounds = const [
      SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
    ];
    await tester.tap(find.byKey(const ValueKey('soundboard-retry')));
    await tester.pumpAndSettle();

    expect(find.text('airhorn'), findsOne);
  });

  testWidgets('a failed read says the soundboard did not arrive', (
    tester,
  ) async {
    final repository = _FakeRepository(failReads: true);
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    expect(find.text('Discord did not return the soundboard.'), findsOne);
  });

  testWidgets('a refused play is reported inside the sheet', (tester) async {
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
      ],
      failWrites: true,
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('soundboard-sound-10')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('soundboard-error')), findsOne);
  });

  testWidgets('a read still running shows progress', (tester) async {
    final gate = Completer<void>();
    final repository = _FakeRepository(
      gate: gate,
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
      ],
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pump();

    expect(find.byKey(const ValueKey('soundboard-loading')), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('airhorn'), findsOne);
  });

  testWidgets('a play in flight shows progress in the sheet', (tester) async {
    final gate = Completer<void>();
    final repository = _FakeRepository(
      sounds: const [
        SoundboardSound(id: '10', name: 'airhorn', guildId: 'guild-1'),
      ],
      writeGate: gate,
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('soundboard-sound-10')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.played.single.id, '10');
  });

  testWidgets('a sound with no name still gets a tile', (tester) async {
    final repository = _FakeRepository(
      sounds: const [SoundboardSound(id: '10', name: '', guildId: 'guild-1')],
    );
    final controller = SoundboardController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('guild-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();

    expect(find.text('Sound'), findsOne);
    expect(find.text('🔊'), findsOne);
  });
}

final class _FakeRepository implements SoundboardRepository {
  _FakeRepository({
    this.sounds = const [],
    this.failReads = false,
    this.failWrites = false,
    this.gate,
    this.writeGate,
  });

  final StreamController<String> _updates = StreamController.broadcast();
  final StreamController<SoundboardPlayback> _playbacks =
      StreamController.broadcast();
  final List<SoundboardSound> played = [];
  final Completer<void>? gate;
  final Completer<void>? writeGate;
  final bool failReads;
  final bool failWrites;

  List<SoundboardSound> sounds;
  String? _loadedGuild;

  @override
  List<SoundboardSound> soundsFor(String guildId) =>
      _loadedGuild == guildId ? sounds : const [];

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Stream<SoundboardPlayback> get playbacks => _playbacks.stream;

  @override
  Future<List<SoundboardSound>> loadSounds(String guildId) async {
    await gate?.future;
    if (failReads) throw StateError('unreachable');
    _loadedGuild = guildId;
    if (!_updates.isClosed) _updates.add(guildId);
    return sounds;
  }

  @override
  Future<void> playSound(String channelId, SoundboardSound sound) async {
    await writeGate?.future;
    if (failWrites) throw StateError('rejected');
    played.add(sound);
  }

  Future<void> close() async {
    await _updates.close();
    await _playbacks.close();
  }
}
