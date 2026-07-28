import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/message_component.dart';

/// Drives the buttons and selects under a message, and the modals they open.
final class MessageComponentController extends ChangeNotifier {
  MessageComponentController(this._repositoryProvider);

  final MessageComponentRepository? Function() _repositoryProvider;

  MessageComponentRepository? _repository;
  StreamSubscription<ModalDefinition>? _modals;
  bool _bound = false;
  bool _disposed = false;

  String? _channelId;
  String? _guildId;
  final Set<String> _busy = {};
  Object? _error;
  ModalDefinition? _pendingModal;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  /// The modal an application asked to show, or `null`.
  ModalDefinition? get pendingModal => _pendingModal;

  Object? get error => _error;

  /// Whether [messageId]'s components are waiting on a press to land.
  bool isBusy(String messageId) => _busy.contains(messageId);

  /// Points the controller at the conversation on screen.
  void show({required String? channelId, String? guildId}) {
    _bind();
    _channelId = channelId;
    _guildId = guildId;
  }

  /// Presses [component] on [messageId].
  Future<bool> activate({
    required String messageId,
    required String applicationId,
    required MessageComponent component,
    int messageFlags = 0,
    List<String> values = const [],
  }) async {
    final repository = _repository;
    final channelId = _channelId;
    if (repository == null || channelId == null) return false;
    // A link button is handled by opening a browser; there is nothing to send.
    if (component.isLink || !component.isActionable) return false;
    if (!_busy.add(messageId)) return false;
    _error = null;
    _notify();
    try {
      await repository.activate(
        channelId: channelId,
        messageId: messageId,
        applicationId: applicationId,
        component: component,
        guildId: _guildId,
        messageFlags: messageFlags,
        values: values,
      );
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy.remove(messageId);
      _notify();
    }
  }

  /// Sends what was typed into the open modal.
  Future<bool> submitModal(Map<String, String> values) async {
    final repository = _repository;
    final modal = _pendingModal;
    final channelId = _channelId;
    if (repository == null || modal == null || channelId == null) return false;
    _error = null;
    _notify();
    try {
      await repository.submitModal(
        modal,
        channelId: channelId,
        values: values,
        guildId: _guildId,
      );
      _pendingModal = null;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _notify();
    }
  }

  /// Closes the modal without answering it.
  void dismissModal() {
    if (_pendingModal == null) return;
    _pendingModal = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_modals?.cancel());
    _modals = null;
    super.dispose();
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_modals?.cancel());
    _repository = repository;
    _pendingModal = null;
    _modals = repository?.modals.listen(_acceptModal);
    return true;
  }

  void _acceptModal(ModalDefinition modal) {
    _pendingModal = modal;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
