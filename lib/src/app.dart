import 'dart:async';

import 'package:flutter/material.dart';

import 'application/chat_controller.dart';
import 'application/connection_controller.dart';
import 'application/discord_account_connection_controller.dart';
import 'application/discord_friends_controller.dart';
import 'application/discord_oauth_controller.dart';
import 'application/discord_social_dm_controller.dart';
import 'application/discord_social_dm_navigation_controller.dart';
import 'application/discord_social_presence_controller.dart';
import 'application/discord_social_sdk_controller.dart';
import 'application/oauth_guild_directory_controller.dart';
import 'application/oauth_guild_membership_controller.dart';
import 'application/workspace_controller.dart';
import 'application/voice_controller.dart';
import 'data/disconnected_chat_repository.dart';
import 'data/native_attachment_download_service.dart';
import 'data/native_discord_social_sdk_gateway.dart';
import 'data/native_external_link_launcher.dart';
import 'data/unavailable_discord_social_dm_gateway.dart';
import 'data/discord/discord_oauth_account_service.dart';
import 'domain/attachment_download.dart';
import 'domain/chat_repository.dart';
import 'domain/chat_repository_factory.dart';
import 'domain/credential_vault.dart';
import 'domain/discord_oauth.dart';
import 'domain/discord_social_dm.dart';
import 'domain/discord_social_presence.dart';
import 'domain/discord_social_sdk.dart';
import 'domain/voice_audio.dart';
import 'domain/external_link_launcher.dart';
import 'domain/voice_media.dart';
import 'domain/voice_message_recorder.dart';
import 'data/discord/discord_repository_factory.dart';
import 'data/mock_chat_repository.dart';
import 'data/noop_voice_media_service.dart';
import 'data/secure_credential_vault.dart';
import 'data/secure_discord_oauth_vault.dart';
import 'presentation/flucord_shell.dart';
import 'presentation/widgets/discord_account_connection_scope.dart';
import 'presentation/widgets/discord_friends_scope.dart';
import 'presentation/widgets/discord_social_dm_navigation_scope.dart';
import 'presentation/widgets/discord_social_dm_scope.dart';
import 'presentation/widgets/discord_social_presence_scope.dart';
import 'presentation/widgets/discord_social_sdk_scope.dart';
import 'platform/desktop_integration.dart';
import 'theme/flucord_theme.dart';

class FlucordApp extends StatefulWidget {
  const FlucordApp({
    this.initialRepository,
    this.initialSessionMode = SessionMode.disconnected,
    this.restoreSavedSession = true,
    this.credentialVault,
    this.chatRepositoryFactory,
    this.desktopIntegration,
    this.voiceMediaService,
    this.voiceOpusCodecFactory,
    this.voicePlaybackService,
    this.voiceMessageRecorder,
    this.attachmentDownloadService,
    this.externalLinkLauncher,
    this.discordOAuthAccountGateway,
    this.discordSocialSdkGateway,
    this.discordSocialDmGateway,
    this.enableBotTransport = const bool.fromEnvironment(
      'FLUCORD_ENABLE_BOT_TRANSPORT',
    ),
    super.key,
  });

  factory FlucordApp.demo({
    DesktopIntegration? desktopIntegration,
    VoiceMediaService? voiceMediaService,
    VoiceOpusCodecFactory? voiceOpusCodecFactory,
    VoiceAudioPlaybackService? voicePlaybackService,
    VoiceMessageRecorder? voiceMessageRecorder,
    AttachmentDownloadService? attachmentDownloadService,
    ExternalLinkLauncher? externalLinkLauncher,
    DiscordOAuthAccountGateway? discordOAuthAccountGateway,
    DiscordSocialSdkGateway? discordSocialSdkGateway,
    DiscordSocialDmGateway? discordSocialDmGateway,
    bool enableBotTransport = false,
    Key? key,
  }) => FlucordApp(
    initialRepository: MockChatRepository(),
    initialSessionMode: SessionMode.demo,
    restoreSavedSession: false,
    desktopIntegration: desktopIntegration,
    voiceMediaService: voiceMediaService,
    voiceOpusCodecFactory: voiceOpusCodecFactory,
    voicePlaybackService: voicePlaybackService,
    voiceMessageRecorder: voiceMessageRecorder,
    attachmentDownloadService: attachmentDownloadService,
    externalLinkLauncher: externalLinkLauncher,
    discordOAuthAccountGateway: discordOAuthAccountGateway,
    discordSocialSdkGateway: discordSocialSdkGateway,
    discordSocialDmGateway: discordSocialDmGateway,
    enableBotTransport: enableBotTransport,
    key: key,
  );

  final ChatRepository? initialRepository;
  final SessionMode initialSessionMode;
  final bool restoreSavedSession;
  final CredentialVault? credentialVault;
  final ChatRepositoryFactory? chatRepositoryFactory;
  final DesktopIntegration? desktopIntegration;
  final VoiceMediaService? voiceMediaService;
  final VoiceOpusCodecFactory? voiceOpusCodecFactory;
  final VoiceAudioPlaybackService? voicePlaybackService;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final AttachmentDownloadService? attachmentDownloadService;
  final ExternalLinkLauncher? externalLinkLauncher;
  final DiscordOAuthAccountGateway? discordOAuthAccountGateway;
  final DiscordSocialSdkGateway? discordSocialSdkGateway;
  final DiscordSocialDmGateway? discordSocialDmGateway;
  final bool enableBotTransport;

  @override
  State<FlucordApp> createState() => _FlucordAppState();
}

class _FlucordAppState extends State<FlucordApp> {
  late final ChatController _chatController;
  late final ConnectionController _connectionController;
  late final DiscordAccountConnectionController
  _discordAccountConnectionController;
  late final DiscordFriendsController _discordFriendsController;
  late final DiscordOAuthController _discordOAuthController;
  late final DiscordSocialDmController _discordSocialDmController;
  late final DiscordSocialDmNavigationController
  _discordSocialDmNavigationController;
  late final DiscordSocialPresenceController _discordSocialPresenceController;
  late final DiscordSocialSdkController _discordSocialSdkController;
  late final OAuthGuildDirectoryController _oauthGuildDirectoryController;
  late final OAuthGuildMembershipController _oauthGuildMembershipController;
  late final WorkspaceController _workspaceController;
  late final VoiceController _voiceController;
  late final AttachmentDownloadService _attachmentDownloadService;
  late final ExternalLinkLauncher _externalLinkLauncher;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(
      widget.initialRepository ?? const DisconnectedChatRepository(),
    );
    _connectionController = ConnectionController(
      _chatController,
      widget.credentialVault ?? const SecureCredentialVault(),
      widget.chatRepositoryFactory ?? const DiscordBotRepositoryFactory(),
      initialMode: widget.initialSessionMode,
      botTransportEnabled: widget.enableBotTransport,
    );
    _externalLinkLauncher =
        widget.externalLinkLauncher ?? const NativeExternalLinkLauncher();
    final oauthGateway =
        widget.discordOAuthAccountGateway ??
        NativeDiscordOAuthAccountService(
          configuration: DiscordOAuthConfiguration.fromEnvironment(),
          launcher: _externalLinkLauncher,
          vault: const SecureDiscordOAuthGrantVault(),
        );
    _discordOAuthController = DiscordOAuthController(oauthGateway);
    final socialSdkGateway =
        widget.discordSocialSdkGateway ?? NativeDiscordSocialSdkGateway();
    _discordSocialSdkController = DiscordSocialSdkController(socialSdkGateway);
    _discordAccountConnectionController = DiscordAccountConnectionController(
      _discordOAuthController,
      _discordSocialSdkController,
    );
    _discordFriendsController = DiscordFriendsController(socialSdkGateway);
    _discordSocialPresenceController = DiscordSocialPresenceController(
      socialSdkGateway is DiscordSocialPresenceGateway
          ? socialSdkGateway as DiscordSocialPresenceGateway
          : null,
    );
    final socialDmGateway =
        widget.discordSocialDmGateway ??
        switch (socialSdkGateway) {
          final DiscordSocialDmGateway gateway => gateway,
          _ => const UnavailableDiscordSocialDmGateway(),
        };
    _discordSocialDmController = DiscordSocialDmController(socialDmGateway);
    _discordSocialDmNavigationController =
        DiscordSocialDmNavigationController();
    _oauthGuildMembershipController = OAuthGuildMembershipController(
      oauthGateway,
    );
    _oauthGuildDirectoryController = OAuthGuildDirectoryController();
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
    _discordOAuthController.addListener(_syncOAuthAccount);
    _discordSocialSdkController.addListener(_syncSocialSdkAvailability);
    widget.desktopIntegration?.attach(
      chatController: _chatController,
      workspaceController: _workspaceController,
      onProtocolUri: (uri) {
        unawaited(_discordOAuthController.handleProtocolUri(uri));
      },
    );
    _connectionController.initialize(
      restoreSavedSession: widget.restoreSavedSession,
    );
    _discordOAuthController.initialize();
    _discordSocialSdkController.initialize();
  }

  @override
  void dispose() {
    unawaited(widget.desktopIntegration?.dispose());
    _chatController.removeListener(_syncVoiceSignaling);
    _discordOAuthController.removeListener(_syncOAuthAccount);
    _discordSocialSdkController.removeListener(_syncSocialSdkAvailability);
    _chatController.dispose();
    _connectionController.dispose();
    _oauthGuildMembershipController.dispose();
    _discordAccountConnectionController.dispose();
    _discordOAuthController.dispose();
    _discordSocialSdkController.dispose();
    _discordFriendsController.dispose();
    _discordSocialPresenceController.dispose();
    _discordSocialDmController.dispose();
    _discordSocialDmNavigationController.dispose();
    _oauthGuildDirectoryController.dispose();
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

  void _syncOAuthAccount() {
    final account = _discordOAuthController.account;
    _oauthGuildDirectoryController.reconcile(account);
    _oauthGuildMembershipController.reconcileAccount(account?.id);
  }

  void _syncSocialSdkAvailability() {
    _discordFriendsController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordSocialSdkController.isAuthenticated,
    );
    _discordSocialDmController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordSocialSdkController.isAuthenticated,
    );
    _discordSocialPresenceController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordSocialSdkController.isAuthenticated,
    );
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
        home: DiscordAccountConnectionScope(
          controller: _discordAccountConnectionController,
          child: DiscordSocialSdkScope(
            controller: _discordSocialSdkController,
            child: DiscordSocialPresenceScope(
              controller: _discordSocialPresenceController,
              child: DiscordSocialDmNavigationScope(
                controller: _discordSocialDmNavigationController,
                child: DiscordSocialDmScope(
                  controller: _discordSocialDmController,
                  child: DiscordFriendsScope(
                    controller: _discordFriendsController,
                    child: FlucordShell(
                      chatController: _chatController,
                      connectionController: _connectionController,
                      discordOAuthController: _discordOAuthController,
                      oauthGuildDirectoryController:
                          _oauthGuildDirectoryController,
                      oauthGuildMembershipController:
                          _oauthGuildMembershipController,
                      workspaceController: _workspaceController,
                      voiceController: _voiceController,
                      voiceMessageRecorder: widget.voiceMessageRecorder,
                      attachmentDownloadService: _attachmentDownloadService,
                      externalLinkLauncher: _externalLinkLauncher,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
