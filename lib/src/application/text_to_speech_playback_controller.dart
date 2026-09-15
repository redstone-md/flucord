import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_repository.dart';
import '../domain/message_speech.dart';
import 'chat_controller.dart';

/// Reads aloud the spoken-aloud messages that arrive where the user is.
///
/// Only the channel being looked at, while the window has the user's
/// attention: those are the same two facts that make a message count as
/// read, and speech is louder than a highlight. The account's own setting
/// gates the whole thing, read per message because another device can flip
/// it between one message and the next.
///
/// Errors stay off the user's screen. A message that cannot be spoken is
/// still on the timeline, which is the same answer the call sounds give when
/// a machine has no audio device.
final class TextToSpeechPlaybackController extends ChangeNotifier {
  TextToSpeechPlaybackController({
    required ChatController chat,
    required MessageSpeechPlayer? player,
    bool Function()? isSilenced,
  }) : _chat = chat,
       _player = player,
       _isSilenced = isSilenced ?? _neverSilenced {
    _messages = _chat.incomingMessages.listen((event) {
      unawaited(_speak(event));
    });
  }

  static bool _neverSilenced() => false;

  final ChatController _chat;
  final MessageSpeechPlayer? _player;

  /// Whether something, streamer mode, is holding the speakers quiet.
  final bool Function() _isSilenced;

  late final StreamSubscription<Object> _messages;
  bool _disposed = false;

  /// The message most recently read aloud, or null. For the tests that need
  /// to hear what this controller did without mocking a speaker.
  String? _lastSpoken;
  String? get lastSpoken => _lastSpoken;

  /// Why the last message could not be spoken, or null.
  Object? _error;
  Object? get error => _error;

  Future<void> _speak(MessageUpsertedEvent event) async {
    if (_disposed) return;
    final message = event.message;
    final workspace = _chat.workspace;
    final player = _player;
    if (player == null || workspace == null) return;
    if (!event.isNew || message.isSystem || !message.isTextToSpeech) return;
    if (message.authorId == workspace.currentMemberId) return;
    if (message.body.trim().isEmpty) return;
    if (!_chat.allowsTextToSpeech) return;
    if (!_chat.isApplicationActive ||
        message.channelId != _chat.activeChannelId) {
      return;
    }
    if (_isSilenced()) return;
    _lastSpoken = message.body;
    _error = null;
    try {
      await player.speak(message.body);
    } on Object catch (error) {
      _error = error;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_messages.cancel());
    super.dispose();
  }
}
