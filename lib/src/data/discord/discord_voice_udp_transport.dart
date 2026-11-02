import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

final class DiscordVoiceIpDiscovery {
  const DiscordVoiceIpDiscovery({required this.address, required this.port});

  final String address;
  final int port;
}

abstract interface class DiscordVoiceUdpTransport {
  Stream<Uint8List> get packets;

  /// Reports a socket that died after its discovery finished. No more packets
  /// move until the next [discover]. A socket that dies during a discovery
  /// fails that [discover] instead.
  Stream<Object> get socketFailures;

  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  });

  int send(Uint8List packet);
  Future<void> close();
}

abstract final class DiscordVoiceDiscoveryPacket {
  static const size = 74;

  static Uint8List request(int ssrc) {
    final packet = Uint8List(size);
    final data = ByteData.sublistView(packet);
    data.setUint16(0, 1, Endian.big);
    data.setUint16(2, 70, Endian.big);
    data.setUint32(4, ssrc, Endian.big);
    return packet;
  }

  static DiscordVoiceIpDiscovery? parse(Uint8List packet) {
    if (packet.length < size) return null;
    final data = ByteData.sublistView(packet);
    if (data.getUint16(0, Endian.big) != 2 ||
        data.getUint16(2, Endian.big) != 70) {
      return null;
    }
    var addressEnd = 8;
    while (addressEnd < 72 && packet[addressEnd] != 0) {
      addressEnd++;
    }
    if (addressEnd == 8) return null;
    final address = String.fromCharCodes(packet.sublist(8, addressEnd));
    final port = data.getUint16(72, Endian.big);
    if (port == 0) return null;
    return DiscordVoiceIpDiscovery(address: address, port: port);
  }
}

final class IoDiscordVoiceUdpTransport implements DiscordVoiceUdpTransport {
  IoDiscordVoiceUdpTransport({
    Duration discoveryWindow = const Duration(seconds: 5),
    Duration discoveryResend = const Duration(seconds: 1),
  }) : _discoveryWindow = discoveryWindow,
       _discoveryResend = discoveryResend;

  static const _socketClosed = SocketException('Voice UDP socket closed');

  /// How long one discovery may take, and how often it asks again in that
  /// time. A request is a single datagram, and the network may lose it.
  final Duration _discoveryWindow;
  final Duration _discoveryResend;

  final StreamController<Uint8List> _packets = StreamController.broadcast();
  final StreamController<Object> _socketFailures = StreamController.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  InternetAddress? _remoteAddress;
  int? _remotePort;
  Completer<DiscordVoiceIpDiscovery>? _discovery;

  /// Rises with each [discover] and [close]. A discovery reads it after its
  /// waits, to see if a newer call took over the transport in the meantime.
  int _socketClaims = 0;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Stream<Object> get socketFailures => _socketFailures.stream;

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async {
    final claim = ++_socketClaims;
    await _closeSocket();
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw const SocketException('Voice host not found');
    final address = addresses.first;
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    if (claim != _socketClaims) {
      socket.close();
      throw _socketClosed;
    }
    _socket = socket;
    _remoteAddress = address;
    _remotePort = port;
    _subscription = socket.listen(
      _handleSocketEvent,
      onError: (Object error) => _handleSocketLost(socket, error),
      onDone: () => _handleSocketLost(socket, _socketClosed),
    );
    final pending = Completer<DiscordVoiceIpDiscovery>();
    _discovery = pending;
    final request = DiscordVoiceDiscoveryPacket.request(ssrc);
    socket.send(request, address, port);
    final resend = Timer.periodic(
      _discoveryResend,
      (_) => socket.send(request, address, port),
    );
    try {
      return await pending.future.timeout(_discoveryWindow);
    } finally {
      resend.cancel();
      if (identical(_discovery, pending)) _discovery = null;
    }
  }

  /// `dart:io` closes a datagram socket after any failed send. It reports that
  /// once as an error and then as the end of the stream, and every later send
  /// on it returns 0 with no error. Measured on Linux with "message too long"
  /// and "permission denied". Other systems and errors are not measured.
  void _handleSocketLost(RawDatagramSocket socket, Object error) {
    if (!identical(socket, _socket)) return;
    // A running discovery reports the loss to its own caller.
    final discovering = _discovery != null;
    unawaited(_closeSocket(error));
    if (!discovering && !_socketFailures.isClosed) _socketFailures.add(error);
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final packet = Uint8List.fromList(datagram!.data);
      final pending = _discovery;
      if (pending != null && !pending.isCompleted) {
        final result = DiscordVoiceDiscoveryPacket.parse(packet);
        if (result != null) {
          pending.complete(result);
          _discovery = null;
          continue;
        }
      }
      if (!_packets.isClosed) _packets.add(packet);
    }
  }

  @override
  int send(Uint8List packet) {
    final socket = _socket;
    final address = _remoteAddress;
    final port = _remotePort;
    if (socket == null || address == null || port == null) return 0;
    return socket.send(packet, address, port);
  }

  Future<void> _closeSocket([Object reason = _socketClosed]) async {
    final socket = _socket;
    final subscription = _subscription;
    final pending = _discovery;
    _socket = null;
    _subscription = null;
    _remoteAddress = null;
    _remotePort = null;
    _discovery = null;
    if (pending != null && !pending.isCompleted) pending.completeError(reason);
    await subscription?.cancel();
    socket?.close();
  }

  @override
  Future<void> close() async {
    _socketClaims++;
    await _closeSocket();
    await _packets.close();
    await _socketFailures.close();
  }
}
