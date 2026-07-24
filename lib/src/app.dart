import 'dart:async';

import 'package:flutter/material.dart';

import 'application/chat_controller.dart';
import 'application/connection_controller.dart';
import 'application/workspace_controller.dart';
import 'application/voice_controller.dart';
import 'data/native_attachment_download_service.dart';
import 'data/native_external_link_launcher.dart';
import 'domain/attachment_download.dart';
import 'domain/voice_audio.dart';
import 'domain/external_link_launcher.dart';
import 'domain/voice_media.dart';
import 'domain/voice_message_recorder.dart';
import 'data/discord/discord_repository_factory.dart';
import 'data/mock_chat_repository.dart';
import 'data/noop_voice_media_service.dart';
import 'data/secure_credential_vault.dart';
import 'presentation/flucord_shell.dart';
import 'platform/desktop_integration.dart';
import 'theme/flucord_theme.dart';

class FlucordApp extends StatefulWidget {
  const FlucordApp({
    this.desktopIntegration,
    this.voiceMediaService,
    this.voiceOpusCodecFactory,
    this.voicePlaybackService,
    this.voiceMessageRecorder,
    this.attachmentDownloadService,
    this.externalLinkLauncher,
    super.key,
  });

  final DesktopIntegration? desktopIntegration;
  final VoiceMediaService? voiceMediaService;
  final VoiceOpusCodecFactory? voiceOpusCodecFactory;
  final VoiceAudioPlaybackService? voicePlaybackService;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final AttachmentDownloadService? attachmentDownloadService;
  final ExternalLinkLauncher? externalLinkLauncher;

  @override
  State<FlucordApp> createState() => _FlucordAppState();
}

class _FlucordAppState extends State<FlucordApp> {
  late final ChatController _chatController;
  late final ConnectionController _connectionController;
  late final WorkspaceController _workspaceController;
  late final VoiceController _voiceController;
  late final AttachmentDownloadService _attachmentDownloadService;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(MockChatRepository());
    _connectionController = ConnectionController(
      _chatController,
      const SecureCredentialVault(),
      const DiscordBotRepositoryFactory(),
    );
    _workspaceController = WorkspaceController();
    _attachmentDownloadService =
        widget.attachmentDownloadService ?? NativeAttachmentDownloadService();
    _voiceController = VoiceController(
      widget.voiceMediaService ?? const NoopVoiceMediaService(),
      signalingServiceProvider: () => _chatController.voiceSignalingService,
      audioCodecFactory: widget.voiceOpusCodecFactory,
      playbackService: widget.voicePlaybackService,
    );
    _chatController.addListener(_syncVoiceSignaling);
    widget.desktopIntegration?.attach(
      chatController: _chatController,
      workspaceController: _workspaceController,
    );
    _chatController.load();
    _connectionController.initialize();
  }

  @override
  void dispose() {
    unawaited(widget.desktopIntegration?.dispose());
    _chatController.removeListener(_syncVoiceSignaling);
    _chatController.dispose();
    _connectionController.dispose();
    _workspaceController.dispose();
    _voiceController.dispose();
    unawaited(widget.voiceMessageRecorder?.dispose());
    super.dispose();
  }

  void _syncVoiceSignaling() {
    if (_chatController.state == ChatLoadState.ready) {
      unawaited(_voiceController.refreshSignalingService());
    }
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
          voiceController: _voiceController,
          voiceMessageRecorder: widget.voiceMessageRecorder,
          attachmentDownloadService: _attachmentDownloadService,
          externalLinkLauncher:
              widget.externalLinkLauncher ?? const NativeExternalLinkLauncher(),
        ),
      ),
    );
  }
}
