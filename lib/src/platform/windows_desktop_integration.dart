import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

import 'desktop_integration.dart';
import 'desktop_integration_flow.dart';
import 'desktop_protocol_intake.dart';
import 'desktop_tray_coordinator.dart';

/// Windows: updates through a WinSparkle appcast, and a tray that offers
/// them. Everything else is the shared desktop flow.
final class WindowsDesktopIntegration implements DesktopIntegration {
  WindowsDesktopIntegration({AutoDesktopUpdater? updater})
    : this._(updater ?? AutoDesktopUpdater());

  WindowsDesktopIntegration._(AutoDesktopUpdater updater)
    : _flow = DesktopIntegrationFlow(
        protocolIntake: ProtocolHandlerDesktopProtocolIntake(),
        updater: updater,
        trayConfiguration: DesktopTrayConfiguration(
          includeUpdateAction: true,
          updateActionEnabled: updater.hasValidFeedUrl,
        ),
      );

  final DesktopIntegrationFlow _flow;

  @override
  Future<void> initialize() => _flow.initialize();

  @override
  void attach(DesktopAppSurface surface) => _flow.attach(surface);

  @override
  Future<void> dispose() => _flow.dispose();
}

/// Windows updates: auto_updater polls the appcast feed for releases.
/// Without a feed URL (plain debug builds) every call is a no-op.
final class AutoDesktopUpdater implements DesktopUpdater {
  AutoDesktopUpdater({this.feedUrl = _environmentFeedUrl});

  static const _environmentFeedUrl = String.fromEnvironment(
    'FLUCORD_UPDATE_FEED_URL',
  );

  final String feedUrl;
  bool _ready = false;

  /// Whether the feed URL points at an HTTPS host, so the tray can offer
  /// checking for updates.
  bool get hasValidFeedUrl {
    final uri = Uri.tryParse(feedUrl.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  @override
  Future<void> initialize() async {
    if (!hasValidFeedUrl) return;
    try {
      await autoUpdater.setFeedURL(feedUrl.trim());
      await autoUpdater.setScheduledCheckInterval(86400);
      _ready = true;
    } on Object catch (error) {
      _debugFailure('auto updater', error);
    }
  }

  @override
  Future<void> checkForUpdates() async {
    if (_ready) await autoUpdater.checkForUpdates();
  }

  void _debugFailure(String feature, Object error) {
    if (kDebugMode) debugPrint('Flucord $feature unavailable: $error');
  }
}
