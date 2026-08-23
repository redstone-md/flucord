import 'package:flutter/services.dart';

import 'desktop_integration.dart';
import 'desktop_integration_flow.dart';
import 'desktop_protocol_intake.dart';

/// Linux: the GTK runner forwards later flucord:// URLs over a method
/// channel, and launch URLs arrive as process arguments. Everything else is
/// the shared desktop flow.
final class LinuxDesktopIntegration implements DesktopIntegration {
  factory LinuxDesktopIntegration({
    required List<String> initialArguments,
    MethodChannel? channel,
  }) => LinuxDesktopIntegration._(
    MethodChannelDesktopProtocolIntake(
      initialArguments: initialArguments,
      channel: channel ?? MethodChannelDesktopProtocolIntake.defaultChannel,
    ),
  );

  LinuxDesktopIntegration._(DesktopProtocolIntake protocolIntake)
    : _flow = DesktopIntegrationFlow(protocolIntake: protocolIntake);

  final DesktopIntegrationFlow _flow;

  @override
  Future<void> initialize() => _flow.initialize();

  @override
  void attach(DesktopAppSurface surface) => _flow.attach(surface);

  @override
  Future<void> dispose() => _flow.dispose();
}
