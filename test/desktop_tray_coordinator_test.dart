import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/platform/desktop_tray_coordinator.dart';

void main() {
  test(
    'projects the surface unread count and routes every tray action',
    () async {
      final gateway = _TrayGateway();
      var openCount = 0;
      var updateCount = 0;
      var quitCount = 0;
      final coordinator = DesktopTrayCoordinator(
        showWindow: () async => openCount++,
        checkForUpdates: () async => updateCount++,
        quit: () async => quitCount++,
        configuration: const DesktopTrayConfiguration(
          includeUpdateAction: true,
          updateActionEnabled: true,
        ),
        gateway: gateway,
      );
      final surface = _SurfaceStub()..unread = 3;
      addTearDown(coordinator.dispose);
      addTearDown(surface.dispose);

      await coordinator.initialize();
      coordinator.attach(surface);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isReady, isTrue);
      expect(gateway.configuration?.includeUpdateAction, isTrue);
      expect(gateway.configuration?.updateActionEnabled, isTrue);
      expect(gateway.unreadCounts.last, 3);

      surface.unread = 5;
      surface.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.unreadCounts.last, 5);

      // No workspace: the badge keeps what it last showed.
      surface.unread = null;
      surface.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.unreadCounts.last, 5);

      await gateway.emit(DesktopTrayAction.open);
      await gateway.emit(DesktopTrayAction.checkUpdates);
      await gateway.emit(DesktopTrayAction.quit);

      expect(openCount, 1);
      expect(updateCount, 1);
      expect(quitCount, 1);
      expect(gateway.disposeCount, 1);
      expect(coordinator.isReady, isFalse);
    },
  );

  test('does not invoke a disabled update action', () async {
    final gateway = _TrayGateway();
    var updateCount = 0;
    final coordinator = DesktopTrayCoordinator(
      showWindow: () async {},
      checkForUpdates: () async => updateCount++,
      quit: () async {},
      gateway: gateway,
    );
    addTearDown(coordinator.dispose);

    await coordinator.initialize();
    await gateway.emit(DesktopTrayAction.checkUpdates);

    expect(updateCount, 0);
  });
}

final class _SurfaceStub extends ChangeNotifier implements DesktopAppSurface {
  int? unread;

  @override
  int? get unreadChannelCount => unread;

  @override
  String? get activeChannelId => null;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      const Stream.empty();

  @override
  void openChannelLink(ChannelLink link) {}

  @override
  void handleProtocolUri(Uri uri) {}

  @override
  void setApplicationActive(bool value) {}

  @override
  void setWindowVisible(bool value) {}
}

final class _TrayGateway implements DesktopTrayGateway {
  DesktopTrayConfiguration? configuration;
  DesktopTrayActionHandler? onAction;
  final List<int> unreadCounts = [];
  int disposeCount = 0;

  Future<void> emit(DesktopTrayAction action) => onAction!(action);

  @override
  Future<void> initialize({
    required DesktopTrayConfiguration configuration,
    required DesktopTrayActionHandler onAction,
  }) async {
    this.configuration = configuration;
    this.onAction = onAction;
  }

  @override
  Future<void> setUnreadCount(int count) async => unreadCounts.add(count);

  @override
  Future<void> dispose() async {
    disposeCount++;
    onAction = null;
  }
}
