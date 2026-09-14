import 'desktop_integration.dart';
import 'desktop_integration_flow.dart';
import 'desktop_protocol_intake.dart';

/// macOS: protocol URLs through protocol_handler; no updater. Everything
/// else is the shared desktop flow.
final class MacosDesktopIntegration implements DesktopIntegration {
  MacosDesktopIntegration()
    : _flow = DesktopIntegrationFlow(
        protocolIntake: ProtocolHandlerDesktopProtocolIntake(),
      );

  final DesktopIntegrationFlow _flow;

  @override
  Future<void> initialize() => _flow.initialize();

  @override
  void attach(DesktopAppSurface surface) => _flow.attach(surface);

  @override
  Future<void> dispose() => _flow.dispose();
}
