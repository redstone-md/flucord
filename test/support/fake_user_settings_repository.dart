import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

/// An account whose settings load once and never change.
final class FakeUserSettingsRepository implements UserSettingsRepository {
  FakeUserSettingsRepository(this._settings);

  final UserSettings _settings;

  @override
  Stream<UserSettings> get updates => const Stream.empty();

  @override
  UserSettings? get current => null;

  @override
  bool get isLoaded => false;

  @override
  Object? get lastWriteError => null;

  @override
  Future<UserSettings> load() async => _settings;

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {}

  @override
  Future<void> flush() async {}
}
