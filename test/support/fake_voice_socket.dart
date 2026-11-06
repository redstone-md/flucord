/// The voice websocket seam, faked: a test reads the frames the client sent
/// and plays the server's side, down to the code it closes with.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_voice_websocket.dart';

/// Hands every dial the same [socket], and counts the dials.
final class FakeVoiceSocketConnector implements DiscordVoiceSocketConnector {
  FakeVoiceSocketConnector(this.socket);

  final FakeVoiceWebSocket socket;
  int connectCount = 0;
  Uri? lastUri;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    connectCount++;
    lastUri = uri;
    return socket;
  }
}

final class FakeVoiceWebSocket implements DiscordVoiceWebSocket {
  final StreamController<Object?> _messages = StreamController.broadcast();
  final List<Object> sent = [];
  bool _closed = false;

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

  void addBinary(List<int> payload) =>
      _messages.add(Uint8List.fromList(payload));

  /// Closes from the server's side, with the code Discord would send.
  Future<void> closeFromServer(int code) async {
    closeCode = code;
    await _closeMessages();
  }

  /// Set when the socket should behave like one that has closed underneath
  /// the client: `dart:io` throws "StreamSink is closed" on a write.
  bool failSends = false;

  @override
  void send(Object data) {
    if (failSends) throw StateError('StreamSink is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode ??= code;
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
  }
}
