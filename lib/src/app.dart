import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/chat_controller.dart';
import 'application/connection_controller.dart';
import 'application/direct_call_controller.dart';
import 'application/discord_account_connection_controller.dart';
import 'application/discord_desktop_login_controller.dart';
import 'application/discord_friends_controller.dart';
import 'application/discord_oauth_controller.dart';
import 'application/discord_social_activity_controller.dart';
import 'application/discord_social_dm_controller.dart';
import 'application/discord_social_dm_navigation_controller.dart';
import 'application/discord_social_presence_controller.dart';
import 'application/discord_social_sdk_controller.dart';
import 'application/guild_member_list_controller.dart';
import 'application/message_search_controller.dart';
import 'application/self_presence_controller.dart';
import 'application/thread_membership_controller.dart';
import 'application/user_profile_controller.dart';
import 'application/user_settings_controller.dart';
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
import 'data/discord/discord_remote_auth_gateway.dart';
import 'domain/attachment_download.dart';
import 'domain/chat_repository.dart';
import 'domain/chat_repository_factory.dart';
import 'domain/credential_vault.dart';
import 'domain/discord_oauth.dart';
import 'domain/discord_remote_auth.dart';
import 'domain/discord_social_activity.dart';
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
import 'presentation/widgets/discord_desktop_login_scope.dart';
import 'presentation/widgets/discord_friends_scope.dart';
import 'presentation/widgets/discord_social_dm_navigation_scope.dart';
import 'presentation/widgets/discord_social_dm_scope.dart';
import 'presentation/widgets/discord_social_activity_scope.dart';
import 'presentation/widgets/discord_social_presence_scope.dart';
import 'presentation/widgets/discord_social_sdk_scope.dart';
import 'presentation/widgets/self_presence_scope.dart';
import 'presentation/widgets/user_profile_scope.dart';
import 'presentation/widgets/user_settings_scope.dart';
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
    this.discordRemoteAuthGatewayFactory,
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
    DiscordRemoteAuthGatewayFactory? discordRemoteAuthGatewayFactory,
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
    discordRemoteAuthGatewayFactory: discordRemoteAuthGatewayFactory,
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
  final DiscordRemoteAuthGatewayFactory? discordRemoteAuthGatewayFactory;
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
  late final DiscordDesktopLoginController _discordDesktopLoginController;
  late final DiscordOAuthController _discordOAuthController;
  late final DiscordSocialActivityController _discordSocialActivityController;
  late final DiscordSocialDmController _discordSocialDmController;
  late final DiscordSocialDmNavigationController
  _discordSocialDmNavigationController;
  late final DiscordSocialPresenceController _discordSocialPresenceController;
  late final DiscordSocialSdkController _discordSocialSdkController;
  late final OAuthGuildDirectoryController _oauthGuildDirectoryController;
  late final OAuthGuildMembershipController _oauthGuildMembershipController;
  late final WorkspaceController _workspaceController;
  late final GuildMemberListController _memberListController;
  late final MessageSearchController _messageSearchController;
  late final UserSettingsController _userSettingsController;
  late final UserProfileController _userProfileController;
  late final ThreadMembershipController _threadMembershipController;
  late final SelfPresenceController _selfPresenceController;
  late final VoiceController _voiceController;
  late final DirectCallController _directCallController;
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
      widget.chatRepositoryFactory ?? const DiscordRepositoryFactory(),
      initialMode: widget.initialSessionMode,
      botTransportEnabled: widget.enableBotTransport,
    );
    _discordDesktopLoginController = DiscordDesktopLoginController(
      widget.discordRemoteAuthGatewayFactory ??
          const IoDiscordRemoteAuthGatewayFactory(),
      _connectionController,
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
    _discordSocialActivityController = DiscordSocialActivityController(
      socialSdkGateway is DiscordSocialActivityGateway
          ? socialSdkGateway as DiscordSocialActivityGateway
          : null,
    );
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
    // Resolved lazily: the transport is swapped when the session changes, and
    // only the desktop-user one serves member lists.
    _memberListController = GuildMemberListController(
      () => _chatController.memberListRepository,
    );
    // Same reason as the member list: the settings store belongs to whichever
    // transport is signed in, and that is replaced when the session changes.
    _userSettingsController = UserSettingsController(
      () => _chatController.userSettings,
    );
    // Same reason once more: the profile route belongs to the signed-in
    // session, which is replaced when the account changes.
    _userProfileController = UserProfileController(
      () => _chatController.userProfile,
    );
    // Same again: joining a thread is per-account state, and the plane that
    // holds it is swapped out with the session.
    _threadMembershipController = ThreadMembershipController(
      () => _chatController.threadMembership,
    );
    // And again: only a signed-in user's own session can reach the search
    // routes, so the plane is resolved per call rather than captured here.
    _messageSearchController = MessageSearchController(
      () => _chatController.messageSearch,
    );
    // Same again for presence: only a signed-in user session can broadcast a
    // status, and that session is swapped out from under the chrome.
    _selfPresenceController = SelfPresenceController(
      () => _chatController.presenceService,
    );
    _attachmentDownloadService =
        widget.attachmentDownloadService ?? NativeAttachmentDownloadService();
    _voiceController = VoiceController(
      widget.voiceMediaService ?? const NoopVoiceMediaService(),
      signalingServiceProvider: () => _chatController.voiceSignalingService,
      callServiceProvider: () => _chatController.directCallService,
      audioCodecFactory: widget.voiceOpusCodecFactory,
      playbackService: widget.voicePlaybackService,
    );
    _directCallController = DirectCallController(
      serviceProvider: () => _chatController.directCallService,
      voiceController: _voiceController,
    );
    _chatController.addListener(_syncVoiceSignaling);
    _chatController.addListener(_syncUserSettings);
    _chatController.addListener(_syncSelfPresence);
    // R07's non-embedded fallback marks the account active on real input.
    // The handler always answers false so that every key still reaches the
    // widget that was going to receive it.
    ServicesBinding.instance.keyboard.addHandler(_markActiveOnKey);
    _discordOAuthController.addListener(_syncOAuthAccount);
    _discordSocialSdkController.addListener(_syncSocialSdkAvailability);
    _discordAccountConnectionController.addListener(_syncSocialSdkAvailability);
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
    ServicesBinding.instance.keyboard.removeHandler(_markActiveOnKey);
    _chatController.removeListener(_syncVoiceSignaling);
    _chatController.removeListener(_syncUserSettings);
    _chatController.removeListener(_syncSelfPresence);
    _discordOAuthController.removeListener(_syncOAuthAccount);
    _discordSocialSdkController.removeListener(_syncSocialSdkAvailability);
    _discordAccountConnectionController.removeListener(
      _syncSocialSdkAvailability,
    );
    _chatController.dispose();
    _connectionController.dispose();
    _discordDesktopLoginController.dispose();
    _oauthGuildMembershipController.dispose();
    _discordAccountConnectionController.dispose();
    _discordOAuthController.dispose();
    _discordSocialSdkController.dispose();
    _discordFriendsController.dispose();
    _discordSocialActivityController.dispose();
    _discordSocialPresenceController.dispose();
    _discordSocialDmController.dispose();
    _discordSocialDmNavigationController.dispose();
    _oauthGuildDirectoryController.dispose();
    _memberListController.dispose();
    _messageSearchController.dispose();
    _userSettingsController.dispose();
    _userProfileController.dispose();
    _threadMembershipController.dispose();
    _selfPresenceController.dispose();
    _workspaceController.dispose();
    _directCallController.dispose();
    _voiceController.dispose();
    unawaited(widget.voiceMessageRecorder?.dispose());
    super.dispose();
  }

  void _syncVoiceSignaling() {
    if (_chatController.state == ChatLoadState.ready) {
      unawaited(_voiceController.refreshSignalingService());
      _directCallController.reconcileService();
    }
  }

  void _syncUserSettings() {
    _userSettingsController.reconcile();
    _userProfileController.reconcile();
  }

  void _syncSelfPresence() => _selfPresenceController.reconcile();

  bool _markActiveOnKey(KeyEvent event) {
    _selfPresenceController.markActive();
    return false;
  }

  void _syncOAuthAccount() {
    final account = _discordOAuthController.account;
    _oauthGuildDirectoryController.reconcile(account);
    _oauthGuildMembershipController.reconcileAccount(account?.id);
  }

  void _syncSocialSdkAvailability() {
    _discordFriendsController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordAccountConnectionController.socialAccessAllowed,
    );
    _discordSocialDmController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordAccountConnectionController.socialAccessAllowed,
    );
    _discordSocialPresenceController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordAccountConnectionController.socialAccessAllowed,
    );
    _discordSocialActivityController.reconcileSession(
      _discordSocialSdkController.availability,
      authenticated: _discordAccountConnectionController.socialAccessAllowed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _workspaceController,
        _userSettingsController,
        _selfPresenceController,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Flucord',
        debugShowCheckedModeBanner: false,
        theme: FlucordTheme.light,
        darkTheme: FlucordTheme.dark,
        // The account's theme wins whenever it names one Flucord can draw; the
        // rail's toggle stays usable for sessions that have no account behind
        // them, and for a stored theme Flucord does not ship.
        themeMode:
            _userSettingsController.themeMode ?? _workspaceController.themeMode,
        home: SelfPresenceScope(
          controller: _selfPresenceController,
          child: UserProfileScope(
            controller: _userProfileController,
            child: UserSettingsScope(
              controller: _userSettingsController,
              child: DiscordDesktopLoginScope(
                controller: _discordDesktopLoginController,
                child: DiscordAccountConnectionScope(
                  controller: _discordAccountConnectionController,
                  child: DiscordSocialSdkScope(
                    controller: _discordSocialSdkController,
                    child: DiscordSocialActivityScope(
                      controller: _discordSocialActivityController,
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
                                memberListController: _memberListController,
                                messageSearchController:
                                    _messageSearchController,
                                voiceController: _voiceController,
                                threadMembershipController:
                                    _threadMembershipController,
                                directCallController: _directCallController,
                                voiceMessageRecorder:
                                    widget.voiceMessageRecorder,
                                attachmentDownloadService:
                                    _attachmentDownloadService,
                                externalLinkLauncher: _externalLinkLauncher,
                              ),
                            ),
                          ),
                        ),
                      ),
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
