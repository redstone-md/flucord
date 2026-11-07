import 'dart:async';

import 'desktop_integration.dart';
import 'desktop_message_notification_controller.dart';
import 'window_attention.dart';
import '../app_log.dart';

/// Makes a ringing call reach a user whose window is not in front.
///
/// The in-window card is all a ring has while the window is focused. When it
/// is not (minimized, hidden in the tray, or behind other windows), this shows
/// a native toast and flashes the taskbar button. Both go when the ring ends,
/// however it ends, and they follow the window while it rings: raised when it
/// goes behind, lowered when it comes to the front.
final class DesktopCallAlertController {
  DesktopCallAlertController({
    required DesktopFocusProbe isFocused,
    required DesktopNotificationGateway gateway,
    required WindowAttention attention,
  }) : _isFocused = isFocused,
       _gateway = gateway,
       _attention = attention;

  final DesktopFocusProbe _isFocused;

  /// Shared with the message toasts, which own its setup and teardown.
  final DesktopNotificationGateway _gateway;
  final WindowAttention _attention;

  DesktopAppSurface? _surface;
  Future<void> Function()? _showWindow;

  /// The ring being handled, whether or not it raised anything.
  String? _ring;

  /// The ring this controller raised a toast or a flash for.
  String? _raised;

  void attach({
    required DesktopAppSurface surface,
    required Future<void> Function() showWindow,
  }) {
    _surface?.removeListener(_surfaceChanged);
    _surface = surface;
    _showWindow = showWindow;
    surface.addListener(_surfaceChanged);
    _surfaceChanged();
  }

  /// The app announces every change it sees, so only a different ring counts.
  void _surfaceChanged() {
    final ringing = _surface?.ringingCall;
    if (ringing?.identifier == _ring) return;
    _ring = ringing?.identifier;
    unawaited(_lower());
    if (ringing != null) unawaited(_raise(ringing));
  }

  /// Told by the window when it gains or loses the focus.
  void windowFocusChanged({required bool focused}) {
    final ringing = _surface?.ringingCall;
    if (ringing == null || ringing.identifier != _ring) return;
    if (focused) {
      unawaited(_lower());
    } else if (_raised != ringing.identifier) {
      unawaited(_raise(ringing));
    }
  }

  Future<void> _raise(DesktopRingingCall ringing) async {
    final surface = _surface;
    final showWindow = _showWindow;
    if (surface == null || showWindow == null) return;
    if (await _isFocusedSafely()) return;
    // The ring may end at any await below; each step checks it is still on.
    if (_ring != ringing.identifier) return;
    _raised = ringing.identifier;
    await _guard('taskbar flash', _attention.request);
    if (!ringing.showsToast || _ring != ringing.identifier) return;
    await _guard(
      'call notification',
      () => _gateway.show(
        DesktopNotificationRequest(
          identifier: ringing.identifier,
          title: ringing.title,
          body: ringing.body,
          onClick: () async {
            await showWindow();
            surface.openChannelLink(ringing.link);
          },
        ),
      ),
    );
    // Ended while the toast was going up: take it straight down again.
    if (_ring != ringing.identifier) {
      await _guard(
        'call notification',
        () => _gateway.dismiss(ringing.identifier),
      );
    }
  }

  Future<void> _lower() async {
    final raised = _raised;
    if (raised == null) return;
    _raised = null;
    await _guard('taskbar flash', _attention.cancel);
    await _guard('call notification', () => _gateway.dismiss(raised));
  }

  Future<bool> _isFocusedSafely() async {
    try {
      return await _isFocused();
    } on Object catch (error) {
      AppLog.warning('desktop', 'window focus unavailable', error: error);
      return false;
    }
  }

  Future<void> _guard(String feature, Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      AppLog.warning('desktop', '$feature unavailable', error: error);
    }
  }

  Future<void> dispose() async {
    _surface?.removeListener(_surfaceChanged);
    _surface = null;
    _showWindow = null;
    _ring = null;
    await _lower();
  }
}
