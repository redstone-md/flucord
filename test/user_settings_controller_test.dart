import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

void main() {
  test('reports no settings surface when the transport has none', () async {
    final controller = UserSettingsController(() => null);
    addTearDown(controller.dispose);

    controller.reconcile();
    await controller.load();

    expect(controller.isAvailable, isFalse);
    expect(controller.settings, isNull);
    expect(controller.themeMode, isNull);
    expect(controller.writeError, isNull);
    expect(
      await controller.apply(const UserSettingsPatch(quietMode: true)),
      isFalse,
    );
    await controller.flush();
  });

  test(
    'loads once the transport appears and again when it is replaced',
    () async {
      var repository = _Repository();
      final controller = UserSettingsController(() => repository);
      addTearDown(controller.dispose);

      controller.reconcile();
      await pumpEventQueue();
      expect(repository.loads, 1);
      expect(controller.settings, isNotNull);

      // A second reconcile with the same store must not refetch.
      controller.reconcile();
      await pumpEventQueue();
      expect(repository.loads, 1);

      repository = _Repository(theme: UserSettingsTheme.light);
      controller.reconcile();
      await pumpEventQueue();
      expect(repository.loads, 1);
      expect(controller.themeMode, ThemeMode.light);
    },
  );

  test('skips the fetch when the gateway already delivered the blob', () async {
    final repository = _Repository(preloaded: true);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);

    await controller.load();

    expect(repository.loads, 0);
    expect(controller.settings, isNotNull);
    expect(controller.isLoading, isFalse);
  });

  test('surfaces a load failure and clears it on the retry', () async {
    final repository = _Repository(failLoad: true);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.loadError, isA<StateError>());
    expect(controller.settings, isNull);

    repository.failLoad = false;
    await controller.load();
    expect(controller.loadError, isNull);
    expect(controller.settings, isNotNull);
  });

  test('republishes what the store pushes', () async {
    final repository = _Repository();
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.load();
    repository.push(
      const UserSettings(
        appearance: AppearancePreferences(theme: UserSettingsTheme.light),
      ),
    );
    await pumpEventQueue();

    expect(controller.themeMode, ThemeMode.light);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('has no theme opinion for a palette Flucord does not ship', () async {
    final repository = _Repository(theme: UserSettingsTheme.midnight);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.themeMode, isNull);
  });

  test('forwards an edit and refuses one with nothing to save', () async {
    final repository = _Repository(preloaded: true);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.apply(const UserSettingsPatch()), isFalse);
    expect(
      await controller.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      ),
      isTrue,
    );
    expect(repository.applied, hasLength(1));

    await controller.flush();
    expect(repository.flushes, 1);
    expect(controller.writeError, isNull);
  });

  test('refuses an edit while the blob is still on its way', () async {
    final repository = _Repository(blockLoad: true);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);
    controller.reconcile();
    await pumpEventQueue();

    expect(
      await controller.apply(
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      ),
      isFalse,
    );
  });

  test('stops republishing after dispose', () async {
    final repository = _Repository(preloaded: true);
    final controller = UserSettingsController(() => repository);
    controller.reconcile();
    await pumpEventQueue();
    final before = controller.settings;

    controller.dispose();
    repository.push(
      const UserSettings(
        appearance: AppearancePreferences(theme: UserSettingsTheme.light),
      ),
    );
    await pumpEventQueue();

    expect(controller.settings, same(before));
  });
}

final class _Repository implements UserSettingsRepository {
  _Repository({
    this.theme = UserSettingsTheme.dark,
    this.preloaded = false,
    this.failLoad = false,
    this.blockLoad = false,
  }) {
    if (preloaded) {
      _current = UserSettings(appearance: AppearancePreferences(theme: theme));
    }
  }

  final UserSettingsTheme theme;
  final bool preloaded;
  final bool blockLoad;
  bool failLoad;

  final StreamController<UserSettings> _updates = StreamController.broadcast();
  final List<UserSettingsPatch> applied = [];
  UserSettings? _current;
  int loads = 0;
  int flushes = 0;

  void push(UserSettings settings) {
    _current = settings;
    _updates.add(settings);
  }

  @override
  Stream<UserSettings> get updates => _updates.stream;

  @override
  UserSettings? get current => _current;

  @override
  bool get isLoaded => _current != null;

  @override
  Object? get lastWriteError => null;

  @override
  Future<UserSettings> load() async {
    loads++;
    // Stays outstanding so a test can look at the controller mid-flight.
    if (blockLoad) await Completer<UserSettings>().future;
    if (failLoad) throw StateError('offline');
    final settings = UserSettings(
      appearance: AppearancePreferences(theme: theme),
    );
    _current = settings;
    return settings;
  }

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async => applied.add(patch);

  @override
  Future<void> flush() async => flushes++;
}
