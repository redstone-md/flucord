import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/account_entitlements.dart';
import '../domain/soundboard.dart';
import 'account_entitlements_controller.dart';

/// Drives the soundboard picker for the voice channel or call on screen.
///
/// The picker lists every server's sounds the session holds. Which of them
/// play is the account's Nitro: without it, the server the call is in and the
/// defaults; with it, any server's, and the soundboard is offered in DM and
/// group calls too.
final class SoundboardController extends ChangeNotifier {
  SoundboardController(
    this._repositoryProvider, {
    AccountEntitlementsController? entitlements,
  }) : _entitlements = entitlements {
    // Entitlements arrive after the session, and can unlock sounds already on
    // screen.
    entitlements?.addListener(_notifyWhileShown);
  }

  final SoundboardRepository? Function() _repositoryProvider;
  final AccountEntitlementsController? _entitlements;

  SoundboardRepository? _repository;
  StreamSubscription<String>? _updates;
  bool _bound = false;
  bool _disposed = false;

  String? _guildId;
  bool _inCall = false;
  bool _isLoading = false;
  bool _isSending = false;
  bool _loadFailed = false;
  Object? _error;

  /// What has been read on this session, by guild id, or '' for a call's
  /// defaults.
  final Set<String> _loaded = {};

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  /// The server the voice channel belongs to, or null in a call or nowhere.
  String? get guildId => _guildId;

  /// Whether the soundboard button belongs on screen here.
  bool get isOffered =>
      isSupported && (_guildId != null || (_inCall && _reach.everywhere));

  SoundboardCatalogue get catalogue =>
      _repository?.catalogue ?? SoundboardCatalogue.empty;

  /// The picker's sections for what is on screen. See
  /// [SoundboardCatalogue.sections].
  List<SoundboardSection> sections({
    List<String> favoriteIds = const [],
    String query = '',
  }) => catalogue.sections(
    currentGuildId: _guildId,
    favoriteIds: favoriteIds,
    query: query,
  );

  /// Whether [sound] is out of reach until the account has Nitro.
  bool isLocked(SoundboardSound sound) => !_reach.allows(sound);

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  Object? get error => _error;

  /// Whether the last read for what is on screen failed. Sounds held from
  /// before may still be listed, so this is apart from an empty sheet.
  bool get loadFailed => _loadFailed;

  /// Points the controller at a server's voice channel, reading its sounds
  /// the first time. Null clears it.
  void show(String? guildId) => _point(guildId: guildId, inCall: false);

  /// Points the controller at a DM or group call.
  void showCall() => _point(guildId: null, inCall: true);

  Future<void> load() async {
    _bind();
    final repository = _repository;
    final guildId = _guildId;
    if (repository == null || !_isShown || _isLoading) return;
    _isLoading = true;
    _error = null;
    _loadFailed = false;
    _notify();
    try {
      await repository.loadSounds(guildId);
      if (identical(repository, _repository)) _loaded.add(guildId ?? '');
    } on Object catch (error) {
      // A failure for a place no longer on screen is not this one's.
      if (_guildId == guildId) {
        _error = error;
        _loadFailed = true;
      }
    } finally {
      _isLoading = false;
      _notify();
    }
    // Pointed somewhere else while this read was out, which turned that
    // place's own read away. It starts now.
    if (_isShown && !_loaded.contains(_guildId ?? '') && _guildId != guildId) {
      unawaited(load());
    }
  }

  /// Plays [sound] into [channelId].
  Future<bool> play(String channelId, SoundboardSound sound) async {
    final repository = _repository;
    // A sound the server lost its boost level for is shown but cannot be
    // played, and so is one Nitro would unlock: both are refused here rather
    // than sent for a 403.
    if (repository == null ||
        _isSending ||
        !sound.isAvailable ||
        isLocked(sound)) {
      return false;
    }
    _isSending = true;
    _error = null;
    _notify();
    try {
      await repository.playSound(channelId, sound);
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _entitlements?.removeListener(_notifyWhileShown);
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  bool get _isShown => _guildId != null || _inCall;

  SoundboardReach get _reach => SoundboardReach(
    guildId: _guildId,
    everywhere: (_entitlements?.entitlements?.premiumTier ?? PremiumTier.none)
        .usesSoundboardEverywhere,
  );

  void _point({required String? guildId, required bool inCall}) {
    _bind();
    if (_guildId == guildId && _inCall == inCall) return;
    _guildId = guildId;
    _inCall = inCall;
    _error = null;
    _loadFailed = false;
    _notify();
    if (_isShown && !_loaded.contains(guildId ?? '')) unawaited(load());
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen((_) => _notifyWhileShown());
    // A new session has loaded nothing, whatever the last one had. What is
    // on screen reads again; after this call, since a build can bind.
    _loaded.clear();
    if (_isShown && repository != null) {
      scheduleMicrotask(() {
        if (!_disposed) unawaited(load());
      });
    }
    return true;
  }

  void _notifyWhileShown() {
    if (_isShown) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
