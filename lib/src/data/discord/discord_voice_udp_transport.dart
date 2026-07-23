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
  final StreamController<Uint8List> _packets = StreamController.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  InternetAddress? _remoteAddress;
  int? _remotePort;
  Completer<DiscordVoiceIpDiscovery>? _discovery;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async {
    await _closeSocket();
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw const SocketException('Voice host not found');
    _remoteAddress = addresses.first;
    _remotePort = port;
    _socket = await RawDatagramSocket.bind(
      _remoteAddress!.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    _subscription = _socket!.listen(_handleSocketEvent);
    _discovery = Completer<DiscordVoiceIpDiscovery>();
    _socket!.send(
      DiscordVoiceDiscoveryPacket.request(ssrc),
      _remoteAddress!,
      port,
    );
    return _discovery!.future.timeout(const Duration(seconds: 5));
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

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _remoteAddress = null;
    _remotePort = null;
    final pending = _discovery;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const SocketException('Voice UDP socket closed'));
    }
    _discovery = null;
  }

  @override
  Future<void> close() async {
    await _closeSocket();
    await _packets.close();
  }
}
