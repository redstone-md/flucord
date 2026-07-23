import 'dart:io';

abstract interface class DiscordVoiceWebSocket {
  Stream<Object?> get messages;
  int? get closeCode;

  void send(Object data);
  Future<void> close([int? code, String? reason]);
}

abstract interface class DiscordVoiceSocketConnector {
  Future<DiscordVoiceWebSocket> connect(Uri uri);
}

final class IoDiscordVoiceSocketConnector
    implements DiscordVoiceSocketConnector {
  const IoDiscordVoiceSocketConnector();

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async =>
      _IoDiscordVoiceWebSocket(await WebSocket.connect(uri.toString()));
}

final class _IoDiscordVoiceWebSocket implements DiscordVoiceWebSocket {
  _IoDiscordVoiceWebSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  void send(Object data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}
