import 'package:flutter/material.dart';

import 'application/chat_controller.dart';
import 'application/connection_controller.dart';
import 'application/workspace_controller.dart';
import 'data/discord/discord_repository_factory.dart';
import 'data/mock_chat_repository.dart';
import 'data/secure_credential_vault.dart';
import 'presentation/flucord_shell.dart';
import 'theme/flucord_theme.dart';

class FlucordApp extends StatefulWidget {
  const FlucordApp({super.key});

  @override
  State<FlucordApp> createState() => _FlucordAppState();
}

class _FlucordAppState extends State<FlucordApp> {
  late final ChatController _chatController;
  late final ConnectionController _connectionController;
  late final WorkspaceController _workspaceController;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(MockChatRepository());
    _connectionController = ConnectionController(
      _chatController,
      const SecureCredentialVault(),
      const DiscordRepositoryFactory(),
    );
    _workspaceController = WorkspaceController();
    _chatController.load();
    _connectionController.initialize();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _connectionController.dispose();
    _workspaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _workspaceController,
      builder: (context, _) => MaterialApp(
        title: 'Flucord',
        debugShowCheckedModeBanner: false,
        theme: FlucordTheme.light,
        darkTheme: FlucordTheme.dark,
        themeMode: _workspaceController.themeMode,
        home: FlucordShell(
          chatController: _chatController,
          connectionController: _connectionController,
          workspaceController: _workspaceController,
        ),
      ),
    );
  }
}
