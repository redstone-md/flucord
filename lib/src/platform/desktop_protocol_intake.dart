import 'package:flutter/services.dart';
import 'package:protocol_handler/protocol_handler.dart';

import '../domain/channel_link.dart';
import '../app_log.dart';

/// How flucord:// URLs reach the app on this platform.
///
/// [start] registers with the OS and returns the URLs the app was launched
/// with, if any. A URL that arrives while the app runs is handed to the
/// callback given to [start].
abstract interface class DesktopProtocolIntake {
  Future<List<String>> start(void Function(String url) onUrl);

  void dispose();
}

/// Windows and macOS: protocol_handler registers the scheme and delivers
/// later URLs as events.
final class ProtocolHandlerDesktopProtocolIntake
    with ProtocolListener
    implements DesktopProtocolIntake {
  void Function(String url)? _onUrl;
  bool _listening = false;

  @override
  Future<List<String>> start(void Function(String url) onUrl) async {
    _onUrl = onUrl;
    try {
      await protocolHandler.register(ChannelLink.scheme);
      protocolHandler.addListener(this);
      _listening = true;
      final initialUrl = await protocolHandler.getInitialUrl();
      if (initialUrl == null || initialUrl.isEmpty) return const [];
      return [initialUrl];
    } on Object catch (error) {
      _debugFailure('protocol handler', error);
      return const [];
    }
  }

  @override
  void onProtocolUrlReceived(String url) => _onUrl?.call(url);

  @override
  void dispose() {
    _onUrl = null;
    if (!_listening) return;
    _listening = false;
    protocolHandler.removeListener(this);
  }

  void _debugFailure(String feature, Object error) {
    AppLog.warning('desktop', '$feature unavailable', error: error);
  }
}

/// Linux: the GTK runner forwards later URLs over a method channel once the
/// app says it is ready, and launch URLs arrive as process arguments.
final class MethodChannelDesktopProtocolIntake
    implements DesktopProtocolIntake {
  MethodChannelDesktopProtocolIntake({
    required List<String> initialArguments,
    MethodChannel channel = defaultChannel,
  }) : _initialArguments = List.unmodifiable(initialArguments),
       _channel = channel;

  static const defaultChannel = MethodChannel('flucord/protocol');

  final List<String> _initialArguments;
  final MethodChannel _channel;
  void Function(String url)? _onUrl;

  @override
  Future<List<String>> start(void Function(String url) onUrl) async {
    _onUrl = onUrl;
    _channel.setMethodCallHandler(_handleMethodCall);
    await _channel.invokeMethod<void>('ready');
    return _initialArguments;
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    final url = call.arguments;
    if (call.method == 'url' && url is String) {
      _onUrl?.call(url);
    }
    return null;
  }

  @override
  void dispose() {
    _onUrl = null;
    _channel.setMethodCallHandler(null);
  }
}
