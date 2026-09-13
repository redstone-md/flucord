import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/voice_processing.dart';
import 'deep_filter_noise_suppressor.dart';

/// How the worker isolate builds its suppressor.
///
/// A top-level function, and it has to be: this crosses to the worker as a
/// tear-off, and a closure carrying state does not. The recipe is a plain map
/// for the same reason.
typedef SuppressorLoader =
    Future<VoiceNoiseSuppressor> Function(Map<String, Object?> recipe);

/// The noise filter, running on an isolate of its own.
///
/// The model's inference is native CPU work at two rounds per 20 ms frame,
/// fifty frames a second for as long as the microphone is open. On the UI
/// isolate that is a visible stutter under everything else the client does;
/// the model lives where the work is instead, and the caller only ever copies
/// frames across and back.
///
/// The delegate suppressor is built by [loader] inside the worker, so a test
/// can host a stand-in and a release runs the real DeepFilterNet model
/// without this file knowing how either cleans a frame.
final class IsolateNoiseSuppressor implements VoiceNoiseSuppressor {
  IsolateNoiseSuppressor._(this._replies, this._exited) {
    _replySubscription = _replies.listen(_onMessage);
    _exitSubscription = _exited.listen(_onExit);
  }

  static const String _dispose = 'dispose';

  /// Opens the worker and waits for it to answer with its suppressor, or
  /// rethrows whatever building the model threw there.
  static Future<IsolateNoiseSuppressor> open({
    required SuppressorLoader loader,
    required Map<String, Object?> recipe,
  }) async {
    final replies = ReceivePort();
    final exited = ReceivePort();
    final isolate = await Isolate.spawn(
      _entry,
      (replies.sendPort, loader, recipe),
      debugName: 'noise suppressor',
    );
    isolate.addOnExitListener(exited.sendPort);
    final suppressor = IsolateNoiseSuppressor._(replies, exited);
    final answer = await suppressor._ready.future;
    if (answer is! (int, SendPort)) {
      suppressor.dispose();
      isolate.kill(priority: Isolate.immediate);
      throw answer ?? StateError('The noise suppressor isolate exited');
    }
    suppressor._bind(answer.$1, answer.$2);
    return suppressor;
  }

  final ReceivePort _replies;
  final ReceivePort _exited;
  late final StreamSubscription<Object?> _replySubscription;
  late final StreamSubscription<Object?> _exitSubscription;
  final Completer<Object?> _ready = Completer();
  final Map<int, Completer<Int16List>> _pending = {};
  SendPort? _commands;
  int _nextRequestId = 0;
  bool _disposed = false;

  @override
  late final int hopSize;

  @override
  Future<void> process(Int16List frame, {required int channels}) async {
    final commands = _commands;
    if (_disposed || commands == null) {
      throw StateError('IsolateNoiseSuppressor is disposed');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Int16List>();
    _pending[requestId] = completer;
    // A copy: the caller's frame stays theirs while the worker cleans ours.
    commands.send((requestId, Int16List.fromList(frame), channels));
    try {
      final cleaned = await completer.future;
      frame.setAll(0, cleaned);
    } finally {
      _pending.remove(requestId);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _failPending(StateError('IsolateNoiseSuppressor is disposed'));
    // The worker frees the model and ends itself. Nothing kills it from here:
    // a kill could land before the worker read the message, and the model
    // would stay allocated, which is the leak this client is closing.
    _commands?.send(_dispose);
    unawaited(_replySubscription.cancel());
    unawaited(_exitSubscription.cancel());
    _replies.close();
    _exited.close();
  }

  void _bind(int hopSize, SendPort commands) {
    this.hopSize = hopSize;
    _commands = commands;
  }

  /// The first message is the worker's hello: its hop size and where to send
  /// work. Everything after is an answer to a request.
  void _onMessage(Object? message) {
    if (!_ready.isCompleted) {
      _ready.complete(message);
      return;
    }
    if (message is! (int, Object)) return;
    final (requestId, answer) = message;
    final completer = _pending.remove(requestId);
    if (completer == null) return;
    if (answer is Int16List) {
      completer.complete(answer);
    } else {
      completer.completeError(answer);
    }
  }

  /// A worker that died with requests outstanding: the model is gone, and the
  /// caller learns it the way it learns any other suppressor failure.
  void _onExit([Object? _]) {
    if (!_ready.isCompleted) {
      _ready.complete(StateError('The noise suppressor isolate exited'));
      return;
    }
    _failPending(StateError('The noise suppressor isolate exited'));
  }

  void _failPending(Object error) {
    final pending = Map<int, Completer<Int16List>>.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      completer.completeError(error);
    }
  }

  /// A way to open the bundled suppressor on its own isolate, or null when
  /// this build has none: another platform, or a bundle missing the library
  /// or the model.
  ///
  /// Probed once here so a settings surface offers a switch only for a filter
  /// that can actually be switched on.
  static Future<VoiceNoiseSuppressor> Function()? bundledFactory() {
    if (!Platform.isWindows) return null;
    final model = DeepFilterNoiseSuppressor.bundledPath(
      DeepFilterNoiseSuppressor.modelFileName,
    );
    if (!File(model).existsSync()) return null;
    try {
      DynamicLibrary.open(DeepFilterNoiseSuppressor.libraryFileName);
    } on Object {
      return null;
    }
    return () => IsolateNoiseSuppressor.open(
      loader: _openBundledDeepFilter,
      recipe: {
        'library': DeepFilterNoiseSuppressor.libraryFileName,
        'model': model,
      },
    );
  }
}

void _entry((SendPort, SuppressorLoader, Map<String, Object?>) task) async {
  var replyTo = task.$1;
  final loader = task.$2;
  final commands = ReceivePort();
  VoiceNoiseSuppressor suppressor;
  try {
    suppressor = await loader(task.$3);
  } on Object catch (error) {
    replyTo.send(error);
    return;
  }
  replyTo.send((suppressor.hopSize, commands.sendPort));
  // Answers go back in request order: one message is answered before the
  // next is read.
  await for (final message in commands) {
    if (message == IsolateNoiseSuppressor._dispose) {
      suppressor.dispose();
      Isolate.current.kill();
      return;
    }
    final (requestId, frame, channels) = message! as (int, Int16List, int);
    try {
      await suppressor.process(frame, channels: channels);
      replyTo.send((requestId, frame));
    } on Object catch (error) {
      replyTo.send((requestId, error));
    }
  }
}

/// Opens the bundled DeepFilterNet model inside the worker.
Future<VoiceNoiseSuppressor> _openBundledDeepFilter(
  Map<String, Object?> recipe,
) => DeepFilterNoiseSuppressor.open(
  libraryPath: recipe['library']! as String,
  modelPath: recipe['model']! as String,
);
