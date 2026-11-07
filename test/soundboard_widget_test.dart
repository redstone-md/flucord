import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flucord/src/application/account_entitlements_controller.dart';
import 'package:flucord/src/application/expression_favorites_controller.dart';
import 'package:flucord/src/application/soundboard_controller.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/presentation/widgets/soundboard_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    SoundboardController controller, {
    ExpressionFavoritesController? favorites,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => SoundboardButton(
            controller: controller,
            channelId: 'voice-1',
            favorites: favorites,
            guildName: (guildId) => 'Server $guildId',
          ),
        ),
      ),
    ),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('soundboard-open')));
    await tester.pumpAndSettle();
  }

  group('every server', () {
    const home = SoundboardSound(id: '10', name: 'airhorn', guildId: 'home');
    const away = SoundboardSound(id: '20', name: 'drum roll', guildId: 'away');
    const quack = SoundboardSound(id: '1', name: 'quack');

    Future<(_FakeRepository, SoundboardController)> showHome(
      WidgetTester tester, {
      PremiumTier tier = PremiumTier.none,
      ExpressionFavoritesController? favorites,
    }) async {
      final repository = _FakeRepository(sounds: const [away, home, quack]);
      final entitlements = AccountEntitlementsController(
        () => _FakeEntitlements(tier),
      );
      await tester.runAsync(entitlements.load);
      final controller = SoundboardController(
        () => repository,
        entitlements: entitlements,
      );
      addTearDown(controller.dispose);
      addTearDown(entitlements.dispose);
      addTearDown(repository.close);
      await pump(tester, controller, favorites: favorites);
      controller.show('home');
      await tester.pumpAndSettle();
      await openSheet(tester);
      return (repository, controller);
    }

    testWidgets('this server first, then the defaults, then the rest', (
      tester,
    ) async {
      await showHome(tester);

      final order = [
        tester.getTopLeft(find.text('SERVER HOME')).dy,
        tester.getTopLeft(find.text('DEFAULT SOUNDS')).dy,
        tester.getTopLeft(find.text('SERVER AWAY')).dy,
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('without Nitro another server\'s sound is locked', (
      tester,
    ) async {
      final (repository, _) = await showHome(tester);

      expect(
        find.text('Sounds from other servers need Nitro.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('soundboard-sound-20')));
      await tester.pumpAndSettle();
      expect(repository.played, isEmpty);
    });

    testWidgets('with Nitro another server\'s sound plays', (tester) async {
      final (repository, _) = await showHome(tester, tier: PremiumTier.nitro);

      expect(find.text('Sounds from other servers need Nitro.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('soundboard-sound-20')));
      await tester.pumpAndSettle();
      expect(repository.played.single, away);
    });

    testWidgets('search keeps the sounds whose name matches', (tester) async {
      await showHome(tester);

      await tester.enterText(
        find.byKey(const ValueKey('soundboard-search')),
        'DRUM',
      );
      await tester.pumpAndSettle();

      expect(find.text('drum roll'), findsOneWidget);
      expect(find.text('airhorn'), findsNothing);
      expect(find.text('quack'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('soundboard-search')),
        'nothing like it',
      );
      await tester.pumpAndSettle();
      expect(find.text('No sounds match.'), findsOneWidget);
    });

    testWidgets('a star puts the sound in the favourites section', (
      tester,
    ) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);
      addTearDown(store.close);
      await showHome(tester, favorites: favorites);
      expect(find.text('FAVOURITES'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('soundboard-sound-star-20')));
      await tester.pumpAndSettle();

      expect(store.soundWrites.single, ('20', true));
      expect(find.text('FAVOURITES'), findsOneWidget);
      // Listed under favourites and under its own server.
      expect(find.text('drum roll'), findsNWidgets(2));
    });
  });

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
  bool _loaded = false;

  @override
  SoundboardCatalogue get catalogue => _loaded
      ? SoundboardCatalogue(
          defaults: [...sounds.where((sound) => sound.isDefault)],
          byGuild: groupBy(
            sounds.where((sound) => !sound.isDefault),
            (sound) => sound.guildId!,
          ),
        )
      : SoundboardCatalogue.empty;

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Stream<SoundboardPlayback> get playbacks => _playbacks.stream;

  @override
  Future<List<SoundboardSound>> loadSounds(String? guildId) async {
    await gate?.future;
    if (failReads) throw StateError('unreachable');
    _loaded = true;
    if (!_updates.isClosed) _updates.add(guildId ?? '');
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

final class _FakeEntitlements implements AccountEntitlementsRepository {
  _FakeEntitlements(this.tier);

  final PremiumTier tier;

  @override
  Future<AccountEntitlements> loadEntitlements() async =>
      AccountEntitlements(premiumTier: tier);
}

/// Holds starred sounds the way the frecency store does, and nothing else.
final class _FavoritesStore implements ExpressionFavoritesRepository {
  final StreamController<ExpressionFavorites> _updates =
      StreamController.broadcast();
  final List<(String, bool)> soundWrites = [];

  @override
  ExpressionFavorites current = ExpressionFavorites.empty;

  @override
  bool get isLoaded => true;

  @override
  Stream<ExpressionFavorites> get updates => _updates.stream;

  @override
  Future<ExpressionFavorites> load() async => current;

  @override
  Future<bool> setSoundFavorite({
    required String soundId,
    required bool favorite,
  }) async {
    soundWrites.add((soundId, favorite));
    current = current.copyWith(
      soundIds: [
        ...current.soundIds.where((id) => id != soundId),
        if (favorite) soundId,
      ],
    );
    _updates.add(current);
    return true;
  }

  @override
  Future<bool> setGifFavorite({
    required FavoriteGif gif,
    required bool favorite,
  }) => throw UnimplementedError();

  @override
  Future<bool> setStickerFavorite({
    required String stickerId,
    required bool favorite,
  }) => throw UnimplementedError();

  @override
  Future<bool> setEmojiFavorite({
    required String idOrName,
    required bool favorite,
  }) => throw UnimplementedError();

  Future<void> close() => _updates.close();
}
