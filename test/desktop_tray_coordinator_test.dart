import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/platform/desktop_tray_coordinator.dart';

void main() {
  test('projects unread state and routes every tray action', () async {
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
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    addTearDown(chat.dispose);
    addTearDown(coordinator.dispose);
    await chat.load();

    await coordinator.initialize();
    coordinator.attach(chat);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isReady, isTrue);
    expect(gateway.configuration?.includeUpdateAction, isTrue);
    expect(gateway.configuration?.updateActionEnabled, isTrue);
    expect(
      gateway.unreadCounts.last,
      chat.workspace!.channels.where((channel) => channel.unread).length,
    );

    await gateway.emit(DesktopTrayAction.open);
    await gateway.emit(DesktopTrayAction.checkUpdates);
    await gateway.emit(DesktopTrayAction.quit);

    expect(openCount, 1);
    expect(updateCount, 1);
    expect(quitCount, 1);
    expect(gateway.disposeCount, 1);
    expect(coordinator.isReady, isFalse);
  });

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
