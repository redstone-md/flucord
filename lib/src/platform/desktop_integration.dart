import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';

abstract interface class DesktopIntegration {
  Future<void> initialize();

  void attach({
    required ChatController chatController,
    required WorkspaceController workspaceController,
  });

  Future<void> dispose();
}
