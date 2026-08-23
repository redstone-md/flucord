import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/account_standing_controller.dart';
import 'application/auth_session_controller.dart';
import 'application/age_verification_controller.dart';
import 'application/multi_factor_auth_controller.dart';
import 'application/family_centre_controller.dart';
import 'application/friends_controller.dart';
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
import 'application/expression_favorites_controller.dart';
import 'application/self_video_controller.dart';
import 'data/discord/discord_rtp_packet.dart';
import 'data/discord/discord_stream_rtc_service.dart';
import 'data/discord/discord_stream_rtc_session.dart';
import 'application/keybind_controller.dart';
import 'application/remote_camera_controller.dart';
import 'application/streamer_mode_controller.dart';
import 'application/theme_controller.dart';
import 'application/voice_overlay_controller.dart';
import 'data/discord/discord_voice_signaling_service.dart';
import 'data/file_keybind_repository.dart';
import 'data/theme/file_theme_store.dart';
import 'data/file_streamer_mode_repository.dart';
import 'application/gif_picker_controller.dart';
import 'application/go_live_controller.dart';
import 'application/stream_viewer_controller.dart';
import 'application/message_component_controller.dart';
import 'application/slash_command_controller.dart';
import 'application/soundboard_controller.dart';
import 'application/soundboard_playback_controller.dart';
import 'application/stage_controller.dart';
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
import 'domain/chat_models.dart';
import 'domain/attachment_download.dart';
import 'domain/chat_repository.dart';
import 'domain/keybind.dart';
import 'domain/streamer_mode.dart';
import 'domain/chat_repository_factory.dart';
import 'domain/credential_vault.dart';
import 'domain/discord_oauth.dart';
import 'domain/discord_remote_auth.dart';
import 'domain/discord_social_activity.dart';
import 'domain/discord_social_dm.dart';
import 'domain/discord_social_presence.dart';
import 'domain/discord_social_sdk.dart';
import 'domain/soundboard_playback.dart';
import 'domain/video_capture_hub.dart';
import 'domain/video_decoder.dart';
import 'domain/video_encoder.dart';
import 'domain/voice_audio.dart';
import 'domain/external_link_launcher.dart';
import 'domain/voice_connection.dart';
import 'domain/voice_media.dart';
import 'domain/voice_message_recorder.dart';
import 'data/discord/discord_repository_factory.dart';
import 'data/mock_chat_repository.dart';
import 'data/media_kit_soundboard_player.dart';
import 'data/video/native_video_decoder_service.dart';
import 'data/video/clip_recorder.dart';
import 'data/video/screenshot_service.dart';
import 'data/video/native_video_encoder_service.dart';
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
import 'presentation/widgets/account_standing_scope.dart';
import 'presentation/widgets/auth_session_scope.dart';
import 'presentation/widgets/age_verification_scope.dart';
import 'presentation/widgets/multi_factor_auth_scope.dart';
import 'presentation/widgets/keybind_scope.dart';
import 'presentation/widgets/streamer_mode_scope.dart';
import 'presentation/widgets/theme_scope.dart';
import 'presentation/widgets/voice_scope.dart';
import 'presentation/widgets/family_centre_scope.dart';
import 'presentation/widgets/user_profile_scope.dart';
import 'presentation/widgets/user_settings_scope.dart';
import 'platform/desktop_integration.dart';
import 'platform/global_keyboard_hook.dart';
import 'platform/voice_overlay.dart';
import 'platform/window_capture_shield.dart';
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
    this.soundboardAudioPlayer,
    this.videoEncoderService,
    this.videoDecoderService,
    this.keybindRepository,
    this.themeStore,
    this.streamerModeRepository,
    this.windowCaptureShield,
    this.globalKeyboardHook,
    this.screenshotService,
    this.clipRecorder,
    this.voiceOverlay,
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

  /// Overridden in tests, which have no audio device to open.
  final SoundboardAudioPlayer? soundboardAudioPlayer;

  /// Overridden in tests, which have no display to capture.
  final VideoEncoderService? videoEncoderService;

  /// Overridden in tests, which have no decoder to open.
  final VideoDecoderService? videoDecoderService;

  /// Where the keybinds are kept. Injected so a test does not write into
  /// the real support directory.
  final KeybindRepository? keybindRepository;

  /// Where installed themes are read from, injected for the same reason.
  final ThemeStore? themeStore;

  /// Where streamer mode's switches are kept, injected for the same reason.
  final StreamerModeRepository? streamerModeRepository;

  /// Keeps the window out of screen recordings. Injected so a test does not
  /// reach for the real window list.
  final WindowCaptureShield? windowCaptureShield;

  /// Keys from outside this window. Injected so a test does not install a
  /// system-wide hook on the machine running it.
  final GlobalKeyboardHook? globalKeyboardHook;

  /// Saves a picture of the screen. Injected so a test does not read the
  /// display of whoever is running it.
  final ScreenshotService? screenshotService;

  /// Keeps the last few seconds of encoded video, for the clip keybind.
  final ClipRecorder? clipRecorder;

  /// The in-game overlay window. Injected so a test does not put one on the
  /// screen of whoever is running it.
  final VoiceOverlay? voiceOverlay;
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
  late final AccountStandingController _accountStandingController;
  late final FamilyCentreController _familyCentreController;
  late final AuthSessionController _authSessionController;
  late final MultiFactorAuthController _multiFactorAuthController;
  late final AgeVerificationController _ageVerificationController;
  late final FriendsController _friendsController;
  late final ThreadMembershipController _threadMembershipController;
  late final StageController _stageController;
  late final SoundboardController _soundboardController;
  late final GifPickerController _gifPickerController;
  late final ExpressionFavoritesController _expressionFavoritesController;
  late final SoundboardPlaybackController _soundboardPlaybackController;
  late final VideoCaptureHub _videoCapture;
  late final GoLiveController _goLiveController;
  late final StreamViewerController _streamViewerController;
  late final DiscordStreamRtcService _streamRtcService;
  StreamSubscription<DiscordStreamRtcSession>? _streamConnections;
  late final SlashCommandController _slashCommandController;
  late final MessageComponentController _messageComponentController;
  late final SelfPresenceController _selfPresenceController;
  late final VoiceController _voiceController;
  late final SelfVideoController _selfVideoController;
  late final RemoteCameraController _remoteCameraController;
  late final KeybindController _keybindController;
  late final ThemeController _themeController;
  late final StreamerModeController _streamerModeController;
  late final ScreenshotService _screenshotService;
  late final ClipRecorder _clipRecorder;
  late final VoiceOverlayController _voiceOverlayController;
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
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
    // And the safety hub: what Discord has on record belongs to the account
    // that is signed in, not to the application.
    _accountStandingController = AccountStandingController(
      () => _chatController.safetyHub,
    );
    _familyCentreController = FamilyCentreController(
      () => _chatController.familyCentre,
    );
    _authSessionController = AuthSessionController(
      () => _chatController.authSessions,
    );
    _multiFactorAuthController = MultiFactorAuthController(
      () => _chatController.multiFactorAuth,
    );
    // The friend graph belongs to the signed-in session, and is replaced
    // with it: a sign-out must not leave the last account's friends on screen.
    _friendsController = FriendsController(() => _chatController.relationships);
    _ageVerificationController = AgeVerificationController(
      () => _chatController.ageVerification,
      launcher: _externalLinkLauncher,
    );
    // Same again: joining a thread is per-account state, and the plane that
    // holds it is swapped out with the session.
    _threadMembershipController = ThreadMembershipController(
      () => _chatController.threadMembership,
    );
    // And the stage plane, for the same reason: standing in a stage is state
    // that belongs to the signed-in account.
    _stageController = StageController(() => _chatController.stages);
    _soundboardController = SoundboardController(
      () => _chatController.soundboard,
    );
    _gifPickerController = GifPickerController(() => _chatController.gifs);
    // Favourites are account state rather than a picker's own, so the
    // controller follows the session the same way the settings store does.
    _expressionFavoritesController = ExpressionFavoritesController(
      () => _chatController.expressionFavorites,
    );
    // Go Live: the stream plane and the transport binding behind it. The
    // picture comes from the capture module shared with the camera and the
    // clip buffer.
    _videoCapture = VideoCaptureHub(
      encoder: widget.videoEncoderService ?? NativeVideoEncoderService(),
    );
    _goLiveController = GoLiveController(
      repositoryProvider: () => _chatController.goLive,
      capture: _videoCapture,
    );
    // Watching somebody else's share: the decoder and the depacketiser in
    // front of it.
    _streamViewerController = StreamViewerController(
      repositoryProvider: () => _chatController.goLive,
      decoder: widget.videoDecoderService ?? NativeVideoDecoderService(),
    );
    // The second RTC connection a stream lives on. Discord does not carry Go
    // Live over the call's socket: it answers create and watch with an
    // endpoint of their own, and until something dialled it a stream opened,
    // announced itself, and sent nothing.
    _streamRtcService = DiscordStreamRtcService(
      repositoryProvider: () => _chatController.goLive,
      identityProvider: () {
        final signaling = _chatController.voiceSignalingService;
        return signaling is DiscordVoiceSignalingService
            ? signaling.streamIdentity
            : null;
      },
      daveVersionProvider: () {
        final signaling = _chatController.voiceSignalingService;
        return signaling is DiscordVoiceSignalingService
            ? signaling.daveProtocolVersion
            : 0;
      },

      // No DAVE service on the stream socket yet: it announces the call's
      // version so the two agree, but a group of its own is the next problem,
      // not this one.
    );
    _streamConnections = _streamRtcService.opened.listen(_acceptStreamSession);
    _messageComponentController = MessageComponentController(
      () => _chatController.messageComponents,
    );
    _slashCommandController = SlashCommandController(
      () => _chatController.applicationCommands,
    );
    // Discord does not mix a soundboard sound into the voice stream: every
    // client in the channel is told which sound played and fetches it itself.
    _soundboardPlaybackController = SoundboardPlaybackController(
      repositoryProvider: () => _chatController.soundboard,
      connectedChannelId: () => _voiceController.connectedChannelId,
      player: widget.soundboardAudioPlayer ?? MediaKitSoundboardPlayer(),
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
    // The camera reads the live voice session rather than being handed one:
    // a reconnect replaces the transport, and a controller holding the old one
    // would encode into a socket that is already closed.
    _selfVideoController = SelfVideoController(
      capture: _videoCapture,
      transportProvider: () =>
          _chatController.voiceSignalingService is DiscordVoiceSignalingService
          ? (_chatController.voiceSignalingService
                    as DiscordVoiceSignalingService)
                .activeVideoTransport
          : null,
      sinkProvider: () {
        final signaling = _chatController.voiceSignalingService;
        if (signaling is! DiscordVoiceSignalingService) return null;
        return signaling.sendVideoFrame;
      },
      announceSelfVideo: ({required bool enabled}) =>
          _voiceController.setCameraAnnounced(enabled: enabled),
    );
    // Everybody else's cameras. One decoder per sender, made on demand: a room
    // where nobody turns a camera on opens none at all.
    _remoteCameraController = RemoteCameraController(
      packetsProvider: () {
        final signaling = _chatController.voiceSignalingService;
        if (signaling is! DiscordVoiceSignalingService) {
          return const Stream<(String, DiscordRtpFrame)>.empty();
        }
        return signaling.remoteVideo;
      },
      decoderFactory: () =>
          widget.videoDecoderService ?? NativeVideoDecoderService(),
    );
    _keybindController = KeybindController(
      repository: widget.keybindRepository ?? FileKeybindRepository(),
      onTriggered: _runKeybind,
      hook: widget.globalKeyboardHook ?? _defaultKeyboardHook(),
    );
    unawaited(_keybindController.load());
    _themeController = ThemeController(widget.themeStore ?? FileThemeStore());
    unawaited(_themeController.load());
    _streamerModeController = StreamerModeController(
      widget.streamerModeRepository ?? FileStreamerModeRepository(),
      shield: widget.windowCaptureShield ?? _defaultCaptureShield(),
    );
    unawaited(_streamerModeController.load());
    _screenshotService =
        widget.screenshotService ??
        (Platform.isWindows
            ? NativeScreenshotService()
            : const UnavailableScreenshotService());
    _voiceOverlayController = VoiceOverlayController(
      overlay:
          widget.voiceOverlay ??
          (Platform.isWindows
              ? WindowsVoiceOverlay()
              : const UnavailableVoiceOverlay()),
      // Read on demand rather than captured: the overlay is on screen while
      // Flucord is not, so what it says has to come from the live room.
      roster: () => [
        for (final participant in _voiceController.participants)
          OverlaySpeaker(
            name:
                _chatController.workspace
                    ?.memberById(participant.userId)
                    .displayName ??
                participant.userId,
            isSpeaking: participant.isSpeaking,
          ),
      ],
      isHiddenByStreamerMode: () => _streamerModeController.hidesOverlay,
    );
    // Redrawn on every roster change and whenever streamer mode moves: an
    // overlay showing who was in the room a minute ago is worse than none.
    _voiceController.addListener(_refreshOverlay);
    _streamerModeController.addListener(_refreshOverlay);
    _clipRecorder =
        widget.clipRecorder ??
        (Platform.isWindows
            ? NativeClipRecorder()
            : const UnavailableClipRecorder());
    // Fed from the capture module, whichever of its clients is running: a
    // clip is the recording that was already going, and the share and the
    // camera are both that recording.
    _clipRecorder.attach(_videoCapture);
    // Going live is the only streaming this client knows about, so it is
    // what the automatic switch follows.
    _goLiveController.addListener(_syncStreamerMode);

    _chatController.addListener(_syncVoiceSignaling);
    _voiceController.addListener(_syncRemoteCameras);
    _chatController.addListener(_syncUserSettings);
    _chatController.addListener(_syncSelfPresence);
    // R07's non-embedded fallback marks the account active on real input.
    // The handler always answers false so that every key still reaches the
    // widget that was going to receive it.
    ServicesBinding.instance.keyboard.addHandler(_markActiveOnKey);
    // Installed on the keyboard rather than in a Shortcuts widget: a
    // binding has to fire wherever the focus is, including the composer.
    ServicesBinding.instance.keyboard.addHandler(
      _keybindController.handleKeyEvent,
    );
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
    ServicesBinding.instance.keyboard.removeHandler(
      _keybindController.handleKeyEvent,
    );
    _chatController.removeListener(_syncVoiceSignaling);
    _voiceController.removeListener(_syncRemoteCameras);
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
    _accountStandingController.dispose();
    _familyCentreController.dispose();
    _authSessionController.dispose();
    _multiFactorAuthController.dispose();
    _ageVerificationController.dispose();
    _friendsController.dispose();
    _threadMembershipController.dispose();
    _stageController.dispose();
    _soundboardController.dispose();
    _gifPickerController.dispose();
    _expressionFavoritesController.dispose();
    _slashCommandController.dispose();
    _messageComponentController.dispose();
    _soundboardPlaybackController.dispose();
    _goLiveController.dispose();
    _streamViewerController.dispose();
    unawaited(_streamConnections?.cancel());
    unawaited(_streamRtcService.close());
    _selfPresenceController.dispose();
    _workspaceController.dispose();
    _directCallController.dispose();
    _voiceController.dispose();
    _selfVideoController.dispose();
    _remoteCameraController.dispose();
    _goLiveController.removeListener(_syncStreamerMode);

    _voiceController.removeListener(_refreshOverlay);
    _streamerModeController.removeListener(_refreshOverlay);
    _voiceOverlayController.dispose();
    _keybindController.dispose();
    _themeController.dispose();
    _streamerModeController.dispose();
    unawaited(widget.voiceMessageRecorder?.dispose());
    super.dispose();
  }

  void _syncVoiceSignaling() {
    if (_chatController.state == ChatLoadState.ready) {
      unawaited(_voiceController.refreshSignalingService());
      _directCallController.reconcileService();
      _streamRtcService.reconcile();
      unawaited(_runDeveloperCheck());
    }
  }

  /// Joins a channel and starts a share on its own, when asked to by the
  /// environment.
  ///
  /// Screen sharing is the one path that cannot be reached from a test: it
  /// needs a live session, a real voice channel, and Discord's answer to a
  /// stream it actually created. Reaching it meant asking somebody to press a
  /// button and describe what happened, which is how three wrong fixes
  /// happened in a row. Debug builds only, off unless the variables are set:
  ///
  ///   `FLUCORD_DEV_CHANNEL` — the voice channel to join, by name
  ///   `FLUCORD_DEV_GOLIVE=1` — and start sharing once it is up
  Future<void> _runDeveloperCheck() async {
    if (!kDebugMode || _developerCheckRan) return;
    final wanted = Platform.environment['FLUCORD_DEV_CHANNEL'];
    if (wanted == null || wanted.isEmpty) return;
    final workspace = _chatController.workspace;
    final channel = workspace?.channels
        .where(
          (candidate) =>
              candidate.kind == ChannelKind.voice &&
              candidate.name.toLowerCase().contains(wanted.toLowerCase()),
        )
        .firstOrNull;
    if (channel == null) return;
    _developerCheckRan = true;
    developer.log('flucord.dev joining ${channel.name}', name: 'flucord.dev');
    stdout.writeln('flucord.dev joining ${channel.name}');
    await _voiceController.connect(
      guildId: channel.spaceId,
      channelId: channel.id,
    );
    if (Platform.environment['FLUCORD_DEV_GOLIVE'] != '1') return;
    // After the transport has had a moment: a stream created before the call
    // is up is one Discord answers with an endpoint nobody can identify to.
    await Future<void>.delayed(const Duration(seconds: 6));
    stdout.writeln('flucord.dev starting a share');
    await _goLiveController.start(
      channelId: channel.id,
      guildId: channel.spaceId,
    );
  }

  bool _developerCheckRan = false;

  /// Wires a stream connection to whichever end of it this client is.
  ///
  /// Our own stream gets the encoder pointed at it; anybody else's gets its
  /// pictures handed to the viewer. The SSRC only exists once the connection
  /// is ready, so this waits for that rather than reading it here.

  void _acceptStreamSession(DiscordStreamRtcSession session) {
    late final StreamSubscription<VoiceSignalingEvent> events;
    events = session.events.listen((event) {
      if (event is! VoiceTransportReadyEvent) return;
      unawaited(events.cancel());
      if (session.key == _goLiveController.streamKey) {
        // Declared with what the capture is actually running at: the share's
        // profile is the capture module's, not a number of this caller's own.
        session.announceVideo(
          enabled: true,
          settings: _videoCapture.settings ?? VideoCaptureHub.shareSettings,
        );
        _goLiveController.bindTransport(
          ssrc: event.session.ssrc,
          sink: session.sendVideoFrame,
        );
        return;
      }
      // Anything else is somebody else's stream, and its pictures come in
      // here.
      unawaited(
        _streamViewerController.attach(
          session.key,
          packets: session.video.map(
            (packet) => IncomingVideoPacket(
              payload: Uint8List.fromList(packet.$2.payload),
              marker: packet.$2.header.marker,
            ),
          ),
        ),
      );
    });
  }

  /// Reads everybody else's cameras only while a room is actually connected.
  ///
  /// Bound on ready rather than on join: the SSRC map the packets are matched
  /// against is filled from the voice socket, and a listener attached before
  /// it would be reading a socket that has not finished opening.
  /// The theme to draw with, built from whichever palette is in force.
  ThemeData _installedTheme({required bool dark}) =>
      FlucordTheme.fromPalette(_themeController.paletteFor(systemIsDark: dark));

  void _syncRemoteCameras() {
    final connected =
        _voiceController.connectionStatus == VoiceConnectionStatus.ready;
    if (connected == _remoteCameraController.isListening) return;
    if (connected) {
      _remoteCameraController.listen();
    } else {
      _remoteCameraController.stop();
    }
  }

  void _syncUserSettings() {
    _userSettingsController.reconcile();
    _userProfileController.reconcile();
    _soundboardPlaybackController.reconcile();
    _goLiveController.reconcile();
  }

  void _syncSelfPresence() => _selfPresenceController.reconcile();

  void _refreshOverlay() => unawaited(_voiceOverlayController.refresh());

  /// Writes the last few seconds of what was being encoded.
  ///
  /// Only whatever the encoder is already producing: a clip is the recording
  /// that was running, and nothing starts one on the way to saving it.
  Future<void> _saveClip() async {
    final result = await _clipRecorder.save();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        key: const ValueKey('clip-result'),
        content: Text(
          result.isSaved
              ? 'Clip saved to ${result.path}'
              : switch (result.failure) {
                  ClipFailure.empty =>
                    'Nothing to clip: start a stream or a camera first.',
                  ClipFailure.write => 'The clip could not be written.',
                  _ => 'This build cannot save clips.',
                },
        ),
      ),
    );
  }

  /// Writes a screenshot and says where it went.
  ///
  /// Reported through the same messenger the rest of the client speaks with:
  /// a screenshot saved with no acknowledgement is one nobody can find, and
  /// one that failed silently is worse.
  Future<void> _saveScreenshot() async {
    final result = await _screenshotService.save();
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('screenshot-result'),
        content: Text(
          result.isSaved
              ? 'Screenshot saved to ${result.path}'
              : result.failure == ScreenshotFailure.write
              ? 'The screenshot could not be written to disk.'
              : 'This build cannot capture the screen.',
        ),
      ),
    );
  }

  /// The hook this platform has, or one that plainly says it has none.
  static GlobalKeyboardHook _defaultKeyboardHook() => Platform.isWindows
      ? WindowsGlobalKeyboardHook()
      : const UnavailableGlobalKeyboardHook();

  /// The shield this platform has, or one that plainly says it has none.
  static WindowCaptureShield _defaultCaptureShield() => Platform.isWindows
      ? WindowsWindowCaptureShield()
      : const UnavailableWindowCaptureShield();

  void _syncStreamerMode() => _streamerModeController.reconcileStreaming(
    isStreaming: _goLiveController.isStreaming,
  );

  /// Carries out one bound action.
  ///
  /// Push to talk and push to mute are opposites of each other rather than two
  /// separate mechanisms: both set the mute flag, one on press and one on
  /// release.
  void _runKeybind(KeybindAction action, {required bool pressed}) {
    switch (action) {
      case KeybindAction.pushToTalk:
        unawaited(_voiceController.setMuted(muted: !pressed));
      case KeybindAction.pushToMute:
        unawaited(_voiceController.setMuted(muted: pressed));
      case KeybindAction.toggleMute:
        if (pressed) unawaited(_voiceController.toggleMute());
      case KeybindAction.toggleDeafen:
        if (pressed) unawaited(_voiceController.toggleDeafen());
      case KeybindAction.toggleCamera:
        if (pressed) unawaited(_selfVideoController.toggle());
      case KeybindAction.disconnectFromVoiceChannel:
        if (pressed) unawaited(_voiceController.disconnect());
      case KeybindAction.toggleVoiceChannelChat:
        if (pressed) _workspaceController.toggleVoiceChannelChat();
      case KeybindAction.toggleStreamerMode:
        if (pressed) unawaited(_streamerModeController.toggle());
      case KeybindAction.saveScreenshot:
        if (pressed) unawaited(_saveScreenshot());
      case KeybindAction.saveClip:
        if (pressed) unawaited(_saveClip());
      case KeybindAction.toggleOverlay:
        if (pressed) unawaited(_voiceOverlayController.toggle());
    }
  }

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
        _themeController,
      ]),
      builder: (context, _) => MaterialApp(
        // Held so a keybind can say where a screenshot went: the action runs
        // from the keyboard rather than from a widget, and has no context of
        // its own to find a messenger through.
        scaffoldMessengerKey: _messengerKey,
        title: 'Flucord',
        debugShowCheckedModeBanner: false,
        // An installed theme carries its own light-or-dark answer, so it is
        // given to both slots: somebody who chose a dark theme did not ask for
        // it to turn pale when the account's setting says light.
        theme: _installedTheme(dark: false),
        darkTheme: _installedTheme(dark: true),
        // The account's theme wins whenever it names one Flucord can draw; the
        // rail's toggle stays usable for sessions that have no account behind
        // them, and for a stored theme Flucord does not ship.
        themeMode:
            _userSettingsController.themeMode ?? _workspaceController.themeMode,
        home: SelfPresenceScope(
          controller: _selfPresenceController,
          child: UserProfileScope(
            controller: _userProfileController,
            child: AccountStandingScope(
              controller: _accountStandingController,
              child: FamilyCentreScope(
                controller: _familyCentreController,
                child: AuthSessionScope(
                  controller: _authSessionController,
                  child: MultiFactorAuthScope(
                    controller: _multiFactorAuthController,
                    child: AgeVerificationScope(
                      controller: _ageVerificationController,
                      child: ThemeScope(
                        controller: _themeController,
                        child: VoiceScope(
                          controller: _voiceController,
                          child: StreamerModeScope(
                            controller: _streamerModeController,
                            child: KeybindScope(
                              controller: _keybindController,
                              child: UserSettingsScope(
                                controller: _userSettingsController,
                                child: DiscordDesktopLoginScope(
                                  controller: _discordDesktopLoginController,
                                  child: DiscordAccountConnectionScope(
                                    controller:
                                        _discordAccountConnectionController,
                                    child: DiscordSocialSdkScope(
                                      controller: _discordSocialSdkController,
                                      child: DiscordSocialActivityScope(
                                        controller:
                                            _discordSocialActivityController,
                                        child: DiscordSocialPresenceScope(
                                          controller:
                                              _discordSocialPresenceController,
                                          child: DiscordSocialDmNavigationScope(
                                            controller:
                                                _discordSocialDmNavigationController,
                                            child: DiscordSocialDmScope(
                                              controller:
                                                  _discordSocialDmController,
                                              child: DiscordFriendsScope(
                                                controller:
                                                    _discordFriendsController,
                                                child: FlucordShell(
                                                  chatController:
                                                      _chatController,
                                                  connectionController:
                                                      _connectionController,
                                                  discordOAuthController:
                                                      _discordOAuthController,
                                                  oauthGuildDirectoryController:
                                                      _oauthGuildDirectoryController,
                                                  oauthGuildMembershipController:
                                                      _oauthGuildMembershipController,
                                                  workspaceController:
                                                      _workspaceController,
                                                  memberListController:
                                                      _memberListController,
                                                  messageSearchController:
                                                      _messageSearchController,
                                                  voiceController:
                                                      _voiceController,
                                                  threadMembershipController:
                                                      _threadMembershipController,
                                                  stageController:
                                                      _stageController,
                                                  soundboardController:
                                                      _soundboardController,
                                                  goLiveController:
                                                      _goLiveController,
                                                  selfVideoController:
                                                      _selfVideoController,
                                                  remoteCameraController:
                                                      _remoteCameraController,
                                                  streamViewerController:
                                                      _streamViewerController,
                                                  gifPickerController:
                                                      _gifPickerController,
                                                  expressionFavoritesController:
                                                      _expressionFavoritesController,
                                                  slashCommandController:
                                                      _slashCommandController,
                                                  messageComponentController:
                                                      _messageComponentController,
                                                  directCallController:
                                                      _directCallController,
                                                  voiceMessageRecorder: widget
                                                      .voiceMessageRecorder,
                                                  attachmentDownloadService:
                                                      _attachmentDownloadService,
                                                  externalLinkLauncher:
                                                      _externalLinkLauncher,
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
