import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/application_command.dart';

/// Drives the slash-command list under the composer.
///
/// A channel's commands are whatever the applications in it declare, so the
/// list is fetched per channel and per query rather than held: a bot added
/// while the client is open changes the answer, and Discord's own client asks
/// again on every keystroke past the slash.
final class SlashCommandController extends ChangeNotifier {
  SlashCommandController(
    this._repositoryProvider, {
    this.debounce = const Duration(milliseconds: 220),
  });

  final ApplicationCommandRepository? Function() _repositoryProvider;

  final Duration debounce;

  ApplicationCommandRepository? _repository;
  Timer? _debounce;
  bool _bound = false;
  bool _disposed = false;

  String? _channelId;
  String? _guildId;
  String _query = '';
  bool _isOpen = false;
  bool _isLoading = false;
  bool _isSending = false;
  Object? _error;
  List<ApplicationCommand> _commands = const [];
  int _generation = 0;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  /// Whether the composer is showing the command list.
  bool get isOpen => _isOpen;

  List<ApplicationCommand> get commands => _commands;
  String get query => _query;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  Object? get error => _error;

  /// Points the controller at the channel the composer is in.
  void show({required String? channelId, String? guildId}) {
    _bind();
    if (_channelId == channelId && _guildId == guildId) return;
    _channelId = channelId;
    _guildId = guildId;
    close();
  }

  /// Reads what the composer holds and opens or closes the list.
  ///
  /// The list belongs to a message that starts with a slash and has not got
  /// to a space yet: `/ban ` is a command being filled in, not a command being
  /// chosen, and `hello /there` is not a command at all.
  void syncComposer(String text) {
    _bind();
    if (!text.startsWith('/')) {
      close();
      return;
    }
    final query = text.substring(1);
    if (query.contains(' ')) {
      close();
      return;
    }
    _isOpen = true;
    if (_query == query && _commands.isNotEmpty) {
      _notify();
      return;
    }
    _query = query;
    _notify();
    _debounce?.cancel();
    _debounce = Timer(debounce, () => unawaited(_search(query)));
  }

  /// Closes the list without clearing what was found, so reopening is instant.
  void close() {
    _debounce?.cancel();
    if (!_isOpen) return;
    _isOpen = false;
    _notify();
  }

  /// Runs [command] in the channel on screen.
  Future<bool> invoke(
    ApplicationCommand command, {
    Map<String, Object?> values = const {},
  }) async {
    final repository = _repository;
    final channelId = _channelId;
    if (repository == null || channelId == null || _isSending) return false;
    _isSending = true;
    _error = null;
    _notify();
    try {
      await repository.invoke(
        ApplicationCommandInvocation(
          command: command,
          channelId: channelId,
          guildId: _guildId,
          values: values,
        ),
      );
      close();
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
    _debounce?.cancel();
    _debounce = null;
    super.dispose();
  }

  Future<void> _search(String query) async {
    final repository = _repository;
    final channelId = _channelId;
    if (repository == null || channelId == null) return;
    final generation = ++_generation;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final commands = await repository.searchCommands(channelId, query: query);
      // A slower earlier query must not replace a later one's list.
      if (generation != _generation) return;
      _commands = commands;
    } on Object catch (error) {
      if (generation != _generation) return;
      _error = error;
      _commands = const [];
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    _repository = repository;
    _commands = const [];
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
