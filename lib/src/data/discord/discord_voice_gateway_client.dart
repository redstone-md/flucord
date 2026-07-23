import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_voice_dave_controller.dart';
import 'discord_voice_gateway_protocol.dart';
import 'discord_voice_udp_transport.dart';

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

abstract interface class DiscordVoiceClient {
  Stream<VoiceSignalingEvent> get events;

  Future<void> connect();
  Future<void> close();
}

final class DiscordVoiceGatewayClient implements DiscordVoiceClient {
  DiscordVoiceGatewayClient({
    required VoiceServerCredentials credentials,
    required int maxDaveProtocolVersion,
    VoiceDaveService? daveService,
    DiscordVoiceSocketConnector? socketConnector,
    DiscordVoiceUdpTransport? udpTransport,
  }) : _protocol = DiscordVoiceGatewayProtocol(
         credentials: credentials,
         maxDaveProtocolVersion: maxDaveProtocolVersion,
       ),
       _daveController = daveService == null
           ? null
           : DiscordVoiceDaveController(
               daveService: daveService,
               channelId: credentials.channelId,
               selfUserId: credentials.userId,
             ),
       _socketConnector =
           socketConnector ?? const IoDiscordVoiceSocketConnector(),
       _udpTransport = udpTransport ?? IoDiscordVoiceUdpTransport();

  final DiscordVoiceGatewayProtocol _protocol;
  final DiscordVoiceDaveController? _daveController;
  final DiscordVoiceSocketConnector _socketConnector;
  final DiscordVoiceUdpTransport _udpTransport;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  DiscordVoiceWebSocket? _socket;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _heartbeatAcknowledged = true;
  bool _canResume = false;
  bool _closing = false;
  bool _failed = false;
  int _generation = 0;
  int? _ssrc;
  String? _mode;
  DiscordVoiceIpDiscovery? _discovered;
  VoiceTransportSession? _session;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;
  Stream<Uint8List> get packets => _udpTransport.packets;
  VoiceTransportSession? get session => _session;

  @override
  Future<void> connect() async {
    _closing = false;
    _failed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_closing || _failed) return;
    _emitStatus(
      _canResume
          ? VoiceConnectionStatus.reconnecting
          : VoiceConnectionStatus.connecting,
    );
    final generation = ++_generation;
    try {
      final socket = await _socketConnector.connect(_voiceUri());
      if (_closing || generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _socketSubscription = socket.messages.listen(
        (message) => _onMessage(message, generation),
        onDone: () => _onDone(socket, generation),
        onError: (Object error) => _onSocketError(error, generation),
        cancelOnError: true,
      );
      _send(_canResume ? _protocol.resume() : _protocol.identify());
    } catch (error) {
      _scheduleReconnect(error: error);
    }
  }

  Uri _voiceUri() {
    final endpoint = _protocol.credentials.endpoint.trim();
    final base = Uri.parse(
      endpoint.contains('://') ? endpoint : 'wss://$endpoint',
    );
    return base.replace(
      scheme: 'wss',
      queryParameters: {...base.queryParameters, 'v': '8'},
    );
  }

  void _onMessage(Object? raw, int generation) {
    if (_closing || _failed || generation != _generation) return;
    if (raw is List<int>) {
      _handleBinary(Uint8List.fromList(raw));
      return;
    }
    if (raw is! String) return;
    final Map<String, Object?> payload;
    try {
      payload = (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    _protocol.acceptSequence(payload['seq']);
    final data = payload['d'];
    final opcode = payload['op'];
    if (opcode is int && data is Map) {
      try {
        _executeDaveCommands(
          _daveController?.acceptJson(opcode, data.cast<String, Object?>()) ??
              const [],
        );
      } catch (error) {
        _fail(error);
        return;
      }
    }
    switch (opcode) {
      case 2:
        if (data is Map) {
          unawaited(_handleReady(data.cast<String, Object?>(), generation));
        }
      case 4:
        if (data is Map) _handleSession(data.cast<String, Object?>());
      case 6:
        _heartbeatAcknowledged = true;
      case 8:
        if (data is Map) _handleHello(data.cast<String, Object?>());
      case 9:
        _canResume = true;
        _emitStatus(VoiceConnectionStatus.ready);
    }
  }

  void _handleBinary(Uint8List message) {
    if (message.length < 3) return;
    final sequence = ByteData.sublistView(message).getUint16(0, Endian.big);
    _protocol.acceptSequence(sequence);
    if (!_events.isClosed) {
      _events.add(
        VoiceDaveBinaryEvent(
          opcode: message[2],
          payload: message.sublist(3),
          sequence: sequence,
        ),
      );
    }
    try {
      _executeDaveCommands(
        _daveController?.acceptBinary(
              opcode: message[2],
              payload: message.sublist(3),
            ) ??
            const [],
      );
    } catch (error) {
      _fail(error);
    }
  }

  void _handleHello(Map<String, Object?> data) {
    final rawInterval = data['heartbeat_interval'];
    if (rawInterval is! num || rawInterval <= 0) return;
    _heartbeatTimer?.cancel();
    _heartbeatAcknowledged = true;
    final interval = Duration(milliseconds: rawInterval.round());
    _heartbeatTimer = Timer.periodic(interval, (_) => _heartbeat());
  }

  void _heartbeat() {
    if (!_heartbeatAcknowledged) {
      _scheduleReconnect(error: StateError('Voice heartbeat not acknowledged'));
      return;
    }
    _heartbeatAcknowledged = false;
    _send(_protocol.heartbeat(DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> _handleReady(Map<String, Object?> data, int generation) async {
    final ready = DiscordVoiceReady.tryParse(data);
    if (ready == null) {
      _fail(const FormatException('Invalid Discord voice Ready payload'));
      return;
    }
    final mode = _protocol.selectMode(ready.modes);
    if (mode == null) {
      _fail(StateError('Discord voice server offered no supported AEAD mode'));
      return;
    }
    _ssrc = ready.ssrc;
    _mode = mode;
    _discovered = null;
    _emitStatus(VoiceConnectionStatus.discovering);
    try {
      final discovered = await _udpTransport.discover(
        host: ready.ip,
        port: ready.port,
        ssrc: ready.ssrc,
      );
      if (_closing || _failed || generation != _generation) return;
      _discovered = discovered;
      _emitStatus(VoiceConnectionStatus.negotiating);
      _send(
        _protocol.selectProtocol(
          address: discovered.address,
          port: discovered.port,
          mode: mode,
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  void _handleSession(Map<String, Object?> data) {
    final description = DiscordVoiceSessionDescription.tryParse(data);
    final ssrc = _ssrc;
    final mode = _mode;
    final discovered = _discovered;
    if (description == null ||
        ssrc == null ||
        mode == null ||
        discovered == null) {
      _fail(const FormatException('Invalid Discord voice session description'));
      return;
    }
    if (description.mode != mode ||
        description.daveProtocolVersion > _protocol.maxDaveProtocolVersion) {
      _fail(StateError('Discord selected an unsupported voice protocol'));
      return;
    }
    try {
      _daveController?.activate(description.daveProtocolVersion);
    } catch (error) {
      _fail(error);
      return;
    }
    _session = VoiceTransportSession(
      guildId: _protocol.credentials.guildId,
      ssrc: ssrc,
      address: discovered.address,
      port: discovered.port,
      mode: mode,
      secretKey: description.secretKey,
      daveProtocolVersion: description.daveProtocolVersion,
    );
    _canResume = true;
    _emitStatus(VoiceConnectionStatus.ready);
    if (!_events.isClosed) _events.add(VoiceTransportReadyEvent(_session!));
  }

  void setSpeaking(bool enabled) {
    final ssrc = _ssrc;
    if (ssrc != null) _send(_protocol.speaking(ssrc: ssrc, enabled: enabled));
  }

  int sendPacket(Uint8List packet) => _udpTransport.send(packet);

  void sendDaveMessage({required int opcode, required List<int> payload}) {
    _socket?.send(Uint8List.fromList([opcode, ...payload]));
  }

  void _executeDaveCommands(List<DiscordVoiceDaveCommand> commands) {
    for (final command in commands) {
      switch (command) {
        case DiscordVoiceDaveJsonCommand():
          _send({'op': command.opcode, 'd': command.data});
        case DiscordVoiceDaveBinaryCommand():
          sendDaveMessage(opcode: command.opcode, payload: command.payload);
      }
    }
  }

  void _onSocketError(Object error, int generation) {
    if (generation == _generation) _scheduleReconnect(error: error);
  }

  void _onDone(DiscordVoiceWebSocket socket, int generation) {
    if (_closing || _failed || generation != _generation) return;
    final code = socket.closeCode;
    if ({4004, 4006, 4009, 4011, 4014, 4017, 4020, 4021, 4022}.contains(code)) {
      _fail(StateError('Discord voice connection closed with code $code'));
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect({Object? error}) {
    if (_closing || _failed || _reconnectTimer?.isActive == true) return;
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _discovered = null;
    _session = null;
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _emitStatus(VoiceConnectionStatus.reconnecting, error: error);
    _reconnectTimer = Timer(const Duration(seconds: 2), _open);
  }

  void _fail(Object error) {
    if (_closing || _failed) return;
    _failed = true;
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _discovered = null;
    _session = null;
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.failure, error: error);
  }

  void _send(Map<String, Object?> payload) {
    _socket?.send(jsonEncode(payload));
  }

  void _emitStatus(VoiceConnectionStatus status, {Object? error}) {
    if (!_events.isClosed) {
      _events.add(VoiceSignalingStatusEvent(status, error: error));
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _failed = false;
    _generation++;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _socket?.close();
    await _udpTransport.close();
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.disconnected);
    await _events.close();
  }
}
