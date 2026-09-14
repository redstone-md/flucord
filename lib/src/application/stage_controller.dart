import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/stage_channel.dart';

/// Drives the stage controls: the topic, and whether this account is asking to
/// speak, invited, or already on stage.
final class StageController extends ChangeNotifier {
  StageController(this._repositoryProvider);

  final StageRepository? Function() _repositoryProvider;

  StageRepository? _repository;
  StreamSubscription<String>? _updates;
  bool _bound = false;
  bool _disposed = false;

  String? _channelId;
  bool _canModerate = false;
  bool _isBusy = false;
  Object? _error;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  String? get channelId => _channelId;

  /// The stage running in the channel on screen, or `null` when none is.
  StageInstance? get stage =>
      _channelId == null ? null : _repository?.stageFor(_channelId!);

  StagePresence? get presence =>
      _channelId == null ? null : _repository?.presenceFor(_channelId!);

  /// Where this account stands. Audience is the answer before Discord has said
  /// otherwise, because that is what a stage does to somebody who walks in.
  StageRole get role => presence?.role ?? StageRole.audience;

  String get topic => stage?.topic ?? '';
  bool get isLive => stage != null;
  bool get isBusy => _isBusy;
  Object? get error => _error;

  /// Whether this account may start, rename and end the stage.
  bool get canModerate => _canModerate;

  /// Points the controller at [channelId], or clears it for a channel that is
  /// not a stage.
  ///
  /// [canModerate] travels with the channel because it is a per-channel
  /// permission answer: the same account moderates one stage and not another.
  void show(String? channelId, {bool canModerate = false}) {
    _bind();
    if (_channelId == channelId && _canModerate == canModerate) return;
    _channelId = channelId;
    _canModerate = canModerate;
    _error = null;
    _notify();
  }

  Future<bool> requestToSpeak() =>
      _apply((repository, id) => repository.requestToSpeak(id));

  Future<bool> cancelRequest() =>
      _apply((repository, id) => repository.cancelSpeakRequest(id));

  Future<bool> takeStage() =>
      _apply((repository, id) => repository.setSpeaking(id, speaking: true));

  Future<bool> leaveStage() =>
      _apply((repository, id) => repository.setSpeaking(id, speaking: false));

  /// Opens a stage. Refused outright without the permission, rather than sent
  /// for Discord to reject.
  Future<bool> startStage(String topic, {bool notify = false}) {
    if (!_canModerate) return Future.value(false);
    return _apply(
      (repository, id) => repository.startStage(
        id,
        topic: topic.trim(),
        sendStartNotification: notify,
      ),
    );
  }

  Future<bool> setTopic(String topic) {
    if (!_canModerate) return Future.value(false);
    return _apply(
      (repository, id) => repository.setStageTopic(id, topic.trim()),
    );
  }

  Future<bool> endStage() {
    if (!_canModerate) return Future.value(false);
    return _apply((repository, id) => repository.endStage(id));
  }

  /// Puts somebody on stage, or moves them back to the audience.
  Future<bool> setMemberSpeaking(String userId, {required bool speaking}) {
    if (!_canModerate) return Future.value(false);
    return _apply(
      (repository, id) =>
          repository.setMemberSpeaking(id, userId: userId, speaking: speaking),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  Future<bool> _apply(
    Future<void> Function(StageRepository, String) action,
  ) async {
    final repository = _repository;
    final channelId = _channelId;
    if (repository == null || channelId == null || _isBusy) return false;
    _isBusy = true;
    _error = null;
    _notify();
    try {
      await action(repository, channelId);
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen(_accept);
    return true;
  }

  void _accept(String channelId) {
    if (channelId == _channelId) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
