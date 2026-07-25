import 'dart:async';
import 'dart:convert';

import '../../domain/discord_remote_auth.dart';
import '../../domain/discord_session.dart';
import 'discord_remote_auth_api.dart';
import 'discord_remote_auth_crypto.dart';
import 'discord_desktop_websocket.dart';

typedef RemoteAuthSocketConnector =
    Future<DiscordDesktopWebSocket> Function(Uri uri);

final class IoDiscordRemoteAuthGatewayFactory
    implements DiscordRemoteAuthGatewayFactory {
  const IoDiscordRemoteAuthGatewayFactory();

  @override
  DiscordRemoteAuthGateway create() => DiscordRemoteAuthGatewayClient();
}

final class DiscordRemoteAuthGatewayClient implements DiscordRemoteAuthGateway {
  DiscordRemoteAuthGatewayClient({
    DiscordRemoteAuthApiClient? api,
    RemoteAuthSocketConnector? connectSocket,
    Future<DiscordRemoteAuthCrypto> Function()? createCrypto,
    Uri? gatewayUri,
  }) : _api = api ?? DiscordRemoteAuthApiClient(),
       _connectSocket =
           connectSocket ??
           const PlatformDiscordDesktopWebSocketConnector().connect,
       _createCrypto = createCrypto ?? DiscordRemoteAuthCrypto.generate,
       _gatewayUri =
           gatewayUri ?? Uri.parse('wss://remote-auth-gateway.discord.gg/?v=2');

  final DiscordRemoteAuthApiClient _api;
  final RemoteAuthSocketConnector _connectSocket;
  final Future<DiscordRemoteAuthCrypto> Function() _createCrypto;
  final Uri _gatewayUri;
  final StreamController<DiscordRemoteAuthEvent> _events =
      StreamController.broadcast();

  DiscordRemoteAuthCrypto? _crypto;
  DiscordDesktopWebSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  bool _started = false;
  bool _closed = false;
  bool _terminalEventSent = false;

  @override
  Stream<DiscordRemoteAuthEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started) throw StateError('Remote auth already started');
    _started = true;
    try {
      _crypto = await _createCrypto();
      if (_closed) return;
      final socket = await _connectSocket(_gatewayUri);
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _subscription = socket.messages.listen(
        _accept,
        onError: (Object error, StackTrace stackTrace) =>
            _fail('Discord remote auth connection failed.'),
        onDone: _onDone,
        cancelOnError: true,
      );
    } catch (_) {
      _fail('Discord remote auth is unavailable.');
    }
  }

  void _accept(Object? raw) {
    if (raw is! String || _closed) return;
    try {
      final payload = jsonDecode(raw);
      if (payload is! Map) return;
      final message = payload.cast<String, Object?>();
      switch (message['op']) {
        case 'hello':
          _startHeartbeat(message['heartbeat_interval']);
          _send({
            'op': 'init',
            'encoded_public_key': _crypto!.encodedPublicKey,
          });
        case 'nonce_proof':
          final encryptedNonce = message['encrypted_nonce'];
          if (encryptedNonce is! String) {
            _fail('Discord returned an invalid nonce challenge.');
            return;
          }
          _send({
            'op': 'nonce_proof',
            'proof': _crypto!.nonceProof(encryptedNonce),
          });
        case 'pending_remote_init':
          final fingerprint = message['fingerprint'];
          if (fingerprint is String && fingerprint.isNotEmpty) {
            _emit(DiscordRemoteAuthQrReady(fingerprint));
          }
        case 'pending_ticket':
          _acceptPendingUser(message['encrypted_user_payload']);
        case 'pending_login':
          final ticket = message['ticket'];
          if (ticket is String && ticket.isNotEmpty) {
            unawaited(_finishLogin(ticket));
          }
        case 'cancel':
          _fail('Discord cancelled the QR login.');
      }
    } on FormatException {
      _fail('Discord returned malformed remote auth data.');
    } on Object {
      _fail('Discord remote auth verification failed.');
    }
  }

  void _acceptPendingUser(Object? encryptedPayload) {
    if (encryptedPayload is! String) return;
    final parts = _crypto!.decryptText(encryptedPayload).split(':');
    if (parts.length < 4) return;
    _emit(
      DiscordRemoteAuthUserPending(
        discriminator: parts[1],
        avatarHash: parts[2].isEmpty ? null : parts[2],
        username: parts.sublist(3).join(':'),
      ),
    );
  }

  Future<void> _finishLogin(String ticket) async {
    if (_terminalEventSent || _closed) return;
    try {
      final encryptedToken = await _api.exchangeTicket(ticket);
      final token = _crypto!.decryptText(encryptedToken).trim();
      if (token.isEmpty) throw const FormatException('Empty token');
      _terminalEventSent = true;
      _emit(DiscordRemoteAuthCompleted(DiscordDesktopUserSession(token)));
      await _closeTransport();
    } on Object {
      _fail('Discord did not complete the QR login.');
    }
  }

  void _startHeartbeat(Object? rawInterval) {
    final milliseconds = rawInterval is num ? rawInterval.round() : 0;
    if (milliseconds <= 0) return;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      Duration(milliseconds: milliseconds),
      (_) => _send(const {'op': 'heartbeat'}),
    );
  }

  void _send(Map<String, Object?> payload) {
    if (_socket?.isOpen ?? false) {
      _socket!.send(jsonEncode(payload));
    }
  }

  void _onDone() {
    if (!_closed && !_terminalEventSent) {
      _fail('Discord remote auth connection closed.');
    }
  }

  void _fail(String message) {
    if (_closed || _terminalEventSent) return;
    _terminalEventSent = true;
    _emit(DiscordRemoteAuthFailed(message));
    unawaited(_closeTransport());
  }

  void _emit(DiscordRemoteAuthEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> _closeTransport() async {
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await _socket?.close();
    _api.close();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeTransport();
    await _events.close();
  }

  @override
  String toString() => 'DiscordRemoteAuthGatewayClient(<credentials redacted>)';
}
