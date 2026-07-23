import 'package:flutter/material.dart';

import 'application/chat_controller.dart';
import 'application/workspace_controller.dart';
import 'data/mock_chat_repository.dart';
import 'presentation/flucord_shell.dart';
import 'theme/flucord_theme.dart';

class FlucordApp extends StatefulWidget {
  const FlucordApp({super.key});

  @override
  State<FlucordApp> createState() => _FlucordAppState();
}

class _FlucordAppState extends State<FlucordApp> {
  late final ChatController _chatController;
  late final WorkspaceController _workspaceController;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(MockChatRepository());
    _workspaceController = WorkspaceController();
    _chatController.load();
  }

  @override
  void dispose() {
    _chatController.dispose();
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
          workspaceController: _workspaceController,
        ),
      ),
    );
  }
}
