import 'dart:async';
import 'dart:developer' as developer;

import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import '../proto/proto_message.dart';
import 'discord_rest_client.dart';
import 'discord_user_settings_patch.dart';
import 'discord_user_settings_proto.dart';
import 'discord_user_settings_transport.dart';

/// The account settings store for the desktop-user session.
///
/// Discord treats this blob as shared account state rather than as a local
/// preference file: `READY` hands over the current value, another device's
/// edit arrives as a dispatch, and a write is answered with the merged result.
/// The store therefore keeps the decoded protobuf root — not just the leaves
/// Flucord models — so that every write can clone the stored group instead of
/// rebuilding it and quietly dropping the rest.
final class DiscordUserSettingsRepository implements UserSettingsRepository {
  DiscordUserSettingsRepository(this._transport);

  /// Discord's `INVALID_USER_SETTINGS_DATA`, which means the stored blob and
  /// the one we wrote disagree badly enough that only a re-read can recover.
  static const _invalidUserSettingsData = 50105;

  static const _type = DiscordSettingsProtoType.preloadedUserSettings;

  final DiscordUserSettingsTransport _transport;
  final StreamController<UserSettings> _updates = StreamController.broadcast();

  ProtoMessage? _root;
  UserSettings? _current;
  Object? _lastWriteError;
  ProtoMessage? _pending;
  Timer? _saveTimer;
  Duration? _scheduledDelay;
  Future<UserSettings>? _loadInFlight;
  Future<void>? _writeInFlight;

  @override
  Stream<UserSettings> get updates => _updates.stream;

  @override
  UserSettings? get current => _current;

  @override
  bool get isLoaded => _root != null;

  @override
  Object? get lastWriteError => _lastWriteError;

  /// Feeds a gateway dispatch to the store.
  ///
  /// `READY` carries the blob for the preloaded type, so a healthy session
  /// never spends a request on the `GET`. A dispatch naming a settings type
  /// Flucord has no codec for is dropped rather than misread as this one.
  void acceptGatewayDispatch(String name, Map<String, Object?> data) {
    if (name == 'READY') {
      final blob = data['user_settings_proto'];
      if (blob is String && blob.isNotEmpty) {
        _installBase64(blob, partial: false);
      }
      return;
    }
    if (name != 'USER_SETTINGS_PROTO_UPDATE') return;
    final settings = data['settings'];
    if (settings is! Map) return;
    final envelope = settings.cast<String, Object?>();
    if (envelope['type'] != _type) return;
    final blob = envelope['proto'];
    if (blob is! String) return;
    _installBase64(blob, partial: data['partial'] == true);
  }

  @override
  Future<UserSettings> load() {
    final settings = _current;
    if (settings != null) return Future.value(settings);
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final future = _fetch();
    _loadInFlight = future;
    return future.whenComplete(() => _loadInFlight = null);
  }

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {
    final root = _root;
    if (root == null) {
      throw StateError(
        'User settings cannot be edited before the stored blob has loaded',
      );
    }
    if (patch.isEmpty) return;
    final partial = DiscordUserSettingsPatch.build(root, patch);
    // The optimistic apply uses the same replacement rule the server does, so
    // the surface shows exactly what the write will produce rather than a
    // deep-merged approximation of it.
    _install(DiscordUserSettingsPatch.replaceGroups(root, partial));
    final pending = _pending;
    _pending = pending == null
        ? partial
        : DiscordUserSettingsPatch.replaceGroups(pending, partial);
    _schedule(delay.delay);
  }

  @override
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _scheduledDelay = null;
    return _persist();
  }

  Future<void> close() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pending = null;
    await _writeInFlight;
    await _updates.close();
  }

  /// Coalesces the pending save.
  ///
  /// A settings screen produces bursts of edits, and each one would otherwise
  /// be its own request. Only a strictly shorter delay reschedules: a batched
  /// change arriving behind a deliberate click must not push that click's
  /// write further out.
  void _schedule(Duration delay) {
    // The transport goes away with the session, so a save scheduled after the
    // store closed could only fail against a client that is already shut.
    if (_updates.isClosed) return;
    final scheduled = _scheduledDelay;
    if (_saveTimer != null && scheduled != null && delay >= scheduled) return;
    _saveTimer?.cancel();
    _scheduledDelay = delay;
    _saveTimer = Timer(delay, () => unawaited(_persist()));
  }

  Future<void> _persist() async {
    _saveTimer = null;
    _scheduledDelay = null;
    await _writeInFlight;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    // Never empty: an empty patch is refused by `apply`, and the builder
    // always sets at least one group for a patch that is not.
    final encoded = DiscordUserSettingsProto.encodeBase64(pending.encode());
    final write = _write(encoded);
    _writeInFlight = write;
    try {
      await write;
    } finally {
      if (identical(_writeInFlight, write)) _writeInFlight = null;
    }
  }

  Future<void> _write(String encoded) async {
    try {
      final result = await _transport.writeSettingsProto(
        type: _type,
        settings: encoded,
      );
      _lastWriteError = null;
      if (result.outOfDate) {
        _log('Discord rejected a stale user settings write; changes dropped');
      }
      final settings = result.settings;
      if (settings != null && settings.isNotEmpty) {
        // The response is the whole merged blob, so it replaces the root
        // rather than merging into it.
        _installBase64(settings, partial: false);
      } else {
        _emit();
      }
    } on Object catch (error) {
      _lastWriteError = error;
      _log('Saving user settings failed: $error');
      if (_isInvalidSettingsData(error)) await _reload();
      _emit();
    }
  }

  /// Discord answers `50105` when it will not accept the blob at all. The
  /// stored value is then the only truth left, so it is re-read before the
  /// surface is told anything.
  static bool _isInvalidSettingsData(Object error) =>
      error is DiscordApiException &&
      error.responsePayload?['code'] == _invalidUserSettingsData;

  Future<void> _reload() async {
    try {
      final blob = await _transport.readSettingsProto(_type);
      if (blob != null && blob.isNotEmpty) {
        _installBase64(blob, partial: false);
      }
    } on Object catch (error) {
      _log('Reloading user settings failed: $error');
    }
  }

  Future<UserSettings> _fetch() async {
    final blob = await _transport.readSettingsProto(_type);
    if (blob == null || blob.isEmpty) {
      // An account that has never stored settings is not an error: every
      // group is simply absent and every leaf falls back to its default.
      _install(ProtoMessage());
      return _current!;
    }
    if (!_installBase64(blob, partial: false)) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned user settings that could not be decoded',
      );
    }
    return _current!;
  }

  bool _installBase64(String blob, {required bool partial}) {
    final ProtoMessage decoded;
    try {
      decoded = DiscordUserSettingsProto.decodeRoot(blob);
    } on Object catch (error) {
      _log('Discarding undecodable user settings blob: $error');
      return false;
    }
    final root = _root;
    if (partial && root == null) {
      // A partial update carries only the groups that changed. Installing it as
      // the root would make the repository look loaded while holding a fraction
      // of the settings, and load() would then skip the fetch that fills in the
      // rest — leaving the account permanently short of its own preferences.
      _log('Ignoring a partial settings update received before the full blob.');
      return false;
    }
    _install(
      partial
          ? DiscordUserSettingsPatch.replaceGroups(root!, decoded)
          : decoded,
    );
    return true;
  }

  void _install(ProtoMessage root) {
    _root = root;
    _current = DiscordUserSettingsProto.read(root);
    _emit();
  }

  void _emit() {
    final settings = _current;
    if (settings == null || _updates.isClosed) return;
    _updates.add(settings);
  }

  static void _log(String message) =>
      developer.log(message, name: 'flucord.discord.settings', level: 900);
}
