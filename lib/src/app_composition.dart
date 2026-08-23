import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show GlobalKey, ScaffoldMessengerState;
import 'package:flutter/services.dart';

import 'app_bootstrap.dart';
import 'application/voice_room_coordination.dart';
import 'application/account_connection_coordination.dart';
import 'application/account_standing_controller.dart';
import 'application/age_verification_controller.dart';
import 'application/auth_session_controller.dart';
import 'application/chat_controller.dart';
import 'application/chat_session_coordination.dart';
import 'application/connection_controller.dart';
import 'application/developer_check.dart';
import 'application/desktop_app_surface.dart';
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
import 'application/expression_favorites_controller.dart';
import 'application/family_centre_controller.dart';
import 'application/friends_controller.dart';
import 'application/gif_picker_controller.dart';
import 'application/go_live_controller.dart';
import 'application/guild_member_list_controller.dart';
import 'application/keybind_actions.dart';
import 'application/keybind_controller.dart';
import 'application/message_component_controller.dart';
import 'application/message_search_controller.dart';
import 'application/multi_factor_auth_controller.dart';
import 'application/oauth_guild_directory_controller.dart';
import 'application/oauth_guild_membership_controller.dart';
import 'application/remote_camera_controller.dart';
import 'application/self_presence_controller.dart';
import 'application/self_video_controller.dart';
import 'application/slash_command_controller.dart';
import 'application/soundboard_controller.dart';
import 'application/soundboard_playback_controller.dart';
import 'application/stage_controller.dart';
import 'application/stream_viewer_controller.dart';
import 'application/stream_quality_controller.dart';
import 'application/stream_router.dart';
import 'application/streamer_mode_controller.dart';
import 'application/theme_controller.dart';
import 'application/thread_membership_controller.dart';
import 'application/user_profile_controller.dart';
import 'application/user_settings_controller.dart';
import 'application/voice_controller.dart';
import 'application/voice_overlay_controller.dart';
import 'application/workspace_controller.dart';
import 'data/discord/discord_rtp_packet.dart';
import 'data/discord/discord_stream_rtc_service.dart';
import 'data/discord/discord_voice_signaling_service.dart';
import 'data/disconnected_chat_repository.dart';
import 'data/media_kit_soundboard_player.dart';
import 'data/mock_chat_repository.dart';
import 'data/native_attachment_download_service.dart';
import 'data/native_discord_social_sdk_gateway.dart';
import 'data/native_external_link_launcher.dart';
import 'data/unavailable_discord_social_dm_gateway.dart';
import 'data/discord/discord_oauth_account_service.dart';
import 'data/discord/discord_remote_auth_gateway.dart';
import 'data/discord/discord_repository_factory.dart';
import 'data/file_keybind_repository.dart';
import 'data/file_stream_quality_repository.dart';
import 'data/file_streamer_mode_repository.dart';
import 'data/noop_voice_media_service.dart';
import 'data/secure_credential_vault.dart';
import 'data/secure_discord_oauth_vault.dart';
import 'data/theme/file_theme_store.dart';
import 'data/video/native_video_decoder_service.dart';
import 'data/video/native_video_encoder_service.dart';
import 'data/video/clip_recorder.dart';
import 'data/video/screenshot_service.dart';
import 'domain/attachment_download.dart';
import 'domain/discord_social_activity.dart';
import 'domain/discord_social_dm.dart';
import 'domain/discord_social_presence.dart';
import 'domain/external_link_launcher.dart';
import 'domain/video_capture_hub.dart';
import 'domain/voice_message_recorder.dart';
import 'platform/global_keyboard_hook.dart';
import 'platform/voice_overlay.dart';
import 'platform/window_capture_shield.dart';

/// Builds the application's object graph, and tears it down again.
///
/// One construction site for every part: the app widget holds this, builds
/// scopes over its fields, and does nothing else. Adding a part means
/// declaring the field and constructing it in the plane it belongs to;
/// disposal follows construction in reverse, so nothing is torn down while
/// something still reads it. Tests reach in through [AppBootstrap], which
/// substitutes a leaf here without touching anything downstream of it.
final class AppComposition {
  AppComposition(this.bootstrap) {
    _buildSessionPlane();
    _buildAccountPlane();
    _buildWorkspacePlane();
    _buildStreamPlane();
    _buildVoicePlane();
    _buildChromePlane();
    _coordinate();
  }

  /// What the graph is built from: a substitute for anything a test filled
  /// in, the production default for anything left null.
  final AppBootstrap bootstrap;

  /// Held so a keybind can say where a screenshot went: the action runs
  /// from the keyboard rather than from a widget, and has no context of
  /// its own to find a messenger through.
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Teardown for every constructed part, in construction order;
  /// [dispose] walks it backwards.
  final List<void Function()> _teardown = [];

  late final ChatController chat;
  late final ConnectionController connection;
  late final FlucordAppSurface desktopSurface;
  late final DiscordDesktopLoginController desktopLogin;
  late final ExternalLinkLauncher externalLinkLauncher;
  late final DiscordOAuthController oauth;
  late final DiscordSocialSdkController socialSdk;
  late final DiscordAccountConnectionController accountConnection;
  late final DiscordFriendsController discordFriends;
  late final DiscordSocialActivityController socialActivity;
  late final DiscordSocialPresenceController socialPresence;
  late final DiscordSocialDmController socialDm;
  late final DiscordSocialDmNavigationController socialDmNavigation;
  late final OAuthGuildMembershipController oauthGuildMembership;
  late final OAuthGuildDirectoryController oauthGuildDirectory;
  late final WorkspaceController workspace;
  late final GuildMemberListController memberList;
  late final UserSettingsController userSettings;
  late final UserProfileController userProfile;
  late final AccountStandingController accountStanding;
  late final FamilyCentreController familyCentre;
  late final AuthSessionController authSession;
  late final MultiFactorAuthController multiFactorAuth;
  late final AgeVerificationController ageVerification;
  late final FriendsController friends;
  late final ThreadMembershipController threadMembership;
  late final StageController stage;
  late final SoundboardController soundboard;
  late final GifPickerController gifPicker;
  late final ExpressionFavoritesController expressionFavorites;
  late final MessageComponentController messageComponent;
  late final SlashCommandController slashCommand;
  late final MessageSearchController messageSearch;
  late final SelfPresenceController selfPresence;
  late final VideoCaptureHub videoCapture;
  late final StreamQualityController streamQuality;
  late final GoLiveController goLive;
  late final StreamViewerController streamViewer;
  late final DiscordStreamRtcService streamRtc;
  late final StreamRouter streamRouter;
  late final AttachmentDownloadService attachmentDownload;
  late final VoiceController voice;
  late final DirectCallController directCall;
  late final SoundboardPlaybackController soundboardPlayback;
  late final SelfVideoController selfVideo;
  late final RemoteCameraController remoteCameras;
  late final ThemeController theme;
  late final StreamerModeController streamerMode;
  late final ScreenshotService screenshot;
  late final ClipRecorder clipRecorder;
  late final VoiceOverlayController voiceOverlay;
  late final KeybindActions keybindActions;
  late final KeybindController keybinds;
  late final ChatSessionCoordination sessionCoordination;
  late final VoiceRoomCoordination voiceRoomCoordination;
  late final AccountConnectionCoordination accountCoordination;
  late final DeveloperCheck developerCheck;

  /// Passed straight through from [AppBootstrap]: the recorder belongs to
  /// whoever supplied it, and the composition only disposes it.
  late final VoiceMessageRecorder? voiceMessageRecorder;

  /// The demo preset, resolved rather than repeated: demo mode ships the
  /// mock workspace unless a repository was supplied, and never offers to
  /// restore a saved session into canned data.
  bool get _demo => bootstrap.initialSessionMode == SessionMode.demo;

  /// The call's signaling service while a Discord account is signed in.
  ///
  /// The stream and camera planes borrow from it, because the account's
  /// voice state (its identity, its sockets, its live video transport)
  /// lives with the call, not with them.
  DiscordVoiceSignalingService? get liveVoiceSignaling {
    final signaling = chat.voiceSignalingService;
    return signaling is DiscordVoiceSignalingService ? signaling : null;
  }

  void _buildSessionPlane() {
    chat = _register(
      ChatController(
        bootstrap.initialRepository ??
            (_demo ? MockChatRepository() : const DisconnectedChatRepository()),
      ),
    );
    connection = _register(
      ConnectionController(
        chat,
        bootstrap.credentialVault ?? const SecureCredentialVault(),
        bootstrap.chatRepositoryFactory ?? const DiscordRepositoryFactory(),
        initialMode: bootstrap.initialSessionMode,
        botTransportEnabled: bootstrap.enableBotTransport,
      ),
    );
    desktopLogin = _register(
      DiscordDesktopLoginController(
        bootstrap.discordRemoteAuthGatewayFactory ??
            const IoDiscordRemoteAuthGatewayFactory(),
        connection,
      ),
    );
    externalLinkLauncher =
        bootstrap.externalLinkLauncher ?? const NativeExternalLinkLauncher();
  }

  void _buildAccountPlane() {
    final oauthGateway =
        bootstrap.discordOAuthAccountGateway ??
        NativeDiscordOAuthAccountService(
          configuration: DiscordOAuthConfiguration.fromEnvironment(),
          launcher: externalLinkLauncher,
          vault: const SecureDiscordOAuthGrantVault(),
        );
    oauth = _register(DiscordOAuthController(oauthGateway));
    final socialSdkGateway =
        bootstrap.discordSocialSdkGateway ?? NativeDiscordSocialSdkGateway();
    socialSdk = _register(DiscordSocialSdkController(socialSdkGateway));
    accountConnection = _register(
      DiscordAccountConnectionController(oauth, socialSdk),
    );
    discordFriends = _register(DiscordFriendsController(socialSdkGateway));
    socialActivity = _register(
      DiscordSocialActivityController(
        socialSdkGateway is DiscordSocialActivityGateway
            ? socialSdkGateway as DiscordSocialActivityGateway
            : null,
      ),
    );
    socialPresence = _register(
      DiscordSocialPresenceController(
        socialSdkGateway is DiscordSocialPresenceGateway
            ? socialSdkGateway as DiscordSocialPresenceGateway
            : null,
      ),
    );
    final socialDmGateway =
        bootstrap.discordSocialDmGateway ??
        switch (socialSdkGateway) {
          final DiscordSocialDmGateway gateway => gateway,
          _ => const UnavailableDiscordSocialDmGateway(),
        };
    socialDm = _register(DiscordSocialDmController(socialDmGateway));
    socialDmNavigation = _register(DiscordSocialDmNavigationController());
    oauthGuildMembership = _register(
      OAuthGuildMembershipController(oauthGateway),
    );
    oauthGuildDirectory = _register(OAuthGuildDirectoryController());
  }

  void _buildWorkspacePlane() {
    workspace = _register(WorkspaceController());
    // Everything below resolves its plane off the live session through a
    // provider rather than capturing it: the transport is swapped when the
    // account changes, and a controller holding the old one would talk to a
    // socket that is already closed.
    // Resolved lazily out of the rest too: only the desktop-user transport
    // serves member lists.
    memberList = _register(
      GuildMemberListController(() => chat.memberListRepository),
    );
    userSettings = _register(UserSettingsController(() => chat.userSettings));
    userProfile = _register(UserProfileController(() => chat.userProfile));
    accountStanding = _register(
      AccountStandingController(() => chat.safetyHub),
    );
    familyCentre = _register(FamilyCentreController(() => chat.familyCentre));
    authSession = _register(AuthSessionController(() => chat.authSessions));
    multiFactorAuth = _register(
      MultiFactorAuthController(() => chat.multiFactorAuth),
    );
    ageVerification = _register(
      AgeVerificationController(
        () => chat.ageVerification,
        launcher: externalLinkLauncher,
      ),
    );
    // The friend graph belongs to the signed-in session: a sign-out must
    // not leave the last account's friends on screen.
    friends = _register(FriendsController(() => chat.relationships));
    threadMembership = _register(
      ThreadMembershipController(() => chat.threadMembership),
    );
    stage = _register(StageController(() => chat.stages));
    soundboard = _register(SoundboardController(() => chat.soundboard));
    gifPicker = _register(GifPickerController(() => chat.gifs));
    expressionFavorites = _register(
      ExpressionFavoritesController(() => chat.expressionFavorites),
    );
    messageComponent = _register(
      MessageComponentController(() => chat.messageComponents),
    );
    slashCommand = _register(
      SlashCommandController(() => chat.applicationCommands),
    );
    messageSearch = _register(
      MessageSearchController(() => chat.messageSearch),
    );
    selfPresence = _register(
      SelfPresenceController(() => chat.presenceService),
    );
  }

  void _buildStreamPlane() {
    // Go Live: the stream plane and the transport binding behind it. The
    // picture comes from the capture module shared with the camera and the
    // clip buffer.
    videoCapture = VideoCaptureHub(
      encoder: bootstrap.videoEncoderService ?? NativeVideoEncoderService(),
    );
    // The bitrates the capture runs at, loaded from the machine's own file and
    // kept there: they describe this machine's connection, not the account.
    streamQuality = _register(
      StreamQualityController(
        bootstrap.streamQualityRepository ?? FileStreamQualityRepository(),
        capture: videoCapture,
      ),
    );
    unawaited(streamQuality.load());
    goLive = _register(
      GoLiveController(
        repositoryProvider: () => chat.goLive,
        capture: videoCapture,
      ),
    );
    // Watching somebody else's share: the decoder and the depacketiser in
    // front of it.
    streamViewer = _register(
      StreamViewerController(
        repositoryProvider: () => chat.goLive,
        decoder: bootstrap.videoDecoderService ?? NativeVideoDecoderService(),
      ),
    );
    // The second RTC connection a stream lives on. Discord does not carry Go
    // Live over the call's socket: it answers create and watch with an
    // endpoint of their own, and until something dialled it a stream opened,
    // announced itself, and sent nothing.
    streamRtc = DiscordStreamRtcService(
      repositoryProvider: () => chat.goLive,
      identityProvider: () => liveVoiceSignaling?.streamIdentity,
      // The stream plane dials through the same factory the call does, so
      // the two agree about DAVE without this module knowing a version
      // number.
      socketFactoryProvider: () => liveVoiceSignaling?.socketFactory,
    );
    _teardown.add(() => unawaited(streamRtc.close()));
    // Where a ready stream connection goes. The fork between this account's
    // own share and everybody else's lives here rather than in the widget, so
    // the riskiest wiring in the stream plane has tests of its own.
    streamRouter = StreamRouter(
      opened: streamRtc.opened,
      goLive: goLive,
      viewer: streamViewer,
      capture: videoCapture,
    );
    _teardown.add(streamRouter.dispose);
  }

  void _buildVoicePlane() {
    attachmentDownload =
        bootstrap.attachmentDownloadService ??
        NativeAttachmentDownloadService();
    voice = _register(
      VoiceController(
        bootstrap.voiceMediaService ?? const NoopVoiceMediaService(),
        signalingServiceProvider: () => chat.voiceSignalingService,
        callServiceProvider: () => chat.directCallService,
        audioCodecFactory: bootstrap.voiceOpusCodecFactory,
        playbackService: bootstrap.voicePlaybackService,
      ),
    );
    directCall = _register(
      DirectCallController(
        serviceProvider: () => chat.directCallService,
        voiceController: voice,
      ),
    );
    // Discord does not mix a soundboard sound into the voice stream: every
    // client in the channel is told which sound played and fetches it itself.
    soundboardPlayback = _register(
      SoundboardPlaybackController(
        repositoryProvider: () => chat.soundboard,
        connectedChannelId: () => voice.connectedChannelId,
        player: bootstrap.soundboardAudioPlayer ?? MediaKitSoundboardPlayer(),
      ),
    );
    // The camera reads the live voice session rather than being handed one:
    // a reconnect replaces the transport, and a controller holding the old
    // one would encode into a socket that is already closed.
    selfVideo = _register(
      SelfVideoController(
        capture: videoCapture,
        transportProvider: () => liveVoiceSignaling?.activeVideoTransport,
        sinkProvider: () => liveVoiceSignaling?.sendVideoFrame,
        announceSelfVideo: ({required bool enabled}) =>
            voice.setCameraAnnounced(enabled: enabled),
      ),
    );
    // Everybody else's cameras. One decoder per sender, made on demand: a
    // room where nobody turns a camera on opens none at all.
    remoteCameras = _register(
      RemoteCameraController(
        packetsProvider: () =>
            liveVoiceSignaling?.remoteVideo ??
            const Stream<(String, DiscordRtpFrame)>.empty(),
        decoderFactory: () =>
            bootstrap.videoDecoderService ?? NativeVideoDecoderService(),
      ),
    );
  }

  void _buildChromePlane() {
    theme = _register(
      ThemeController(bootstrap.themeStore ?? FileThemeStore()),
    );
    unawaited(theme.load());
    streamerMode = _register(
      StreamerModeController(
        bootstrap.streamerModeRepository ?? FileStreamerModeRepository(),
        shield: bootstrap.windowCaptureShield ?? _defaultCaptureShield(),
      ),
    );
    unawaited(streamerMode.load());
    screenshot =
        bootstrap.screenshotService ??
        (Platform.isWindows
            ? NativeScreenshotService()
            : const UnavailableScreenshotService());
    voiceOverlay = _register(
      VoiceOverlayController(
        overlay:
            bootstrap.voiceOverlay ??
            (Platform.isWindows
                ? WindowsVoiceOverlay()
                : const UnavailableVoiceOverlay()),
        // Read on demand rather than captured: the overlay is on screen
        // while Flucord is not, so what it says has to come from the live
        // room.
        roster: () => [
          for (final participant in voice.participants)
            OverlaySpeaker(
              name:
                  chat.workspace?.memberById(participant.userId).displayName ??
                  participant.userId,
              isSpeaking: participant.isSpeaking,
            ),
        ],
        isHiddenByStreamerMode: () => streamerMode.hidesOverlay,
      ),
    );
    clipRecorder =
        bootstrap.clipRecorder ??
        (Platform.isWindows
            ? NativeClipRecorder()
            : const UnavailableClipRecorder());
    // Fed from the capture module, whichever of its clients is running: a
    // clip is the recording that was already going, and the share and the
    // camera are both that recording.
    clipRecorder.attach(videoCapture);
    voiceMessageRecorder = bootstrap.voiceMessageRecorder;
    keybindActions = KeybindActions(
      voice: voice,
      selfVideo: selfVideo,
      workspace: workspace,
      streamerMode: streamerMode,
      overlay: voiceOverlay,
      screenshot: screenshot,
      clip: clipRecorder,
      messenger: messengerKey,
    );
    keybinds = _register(
      KeybindController(
        repository: bootstrap.keybindRepository ?? FileKeybindRepository(),
        onTriggered: keybindActions.call,
        hook: bootstrap.globalKeyboardHook ?? _defaultKeyboardHook(),
      ),
    );
    unawaited(keybinds.load());
  }

  /// The rules that couple controllers to each other. Constructed last, so
  /// they are the first thing torn down: no controller is disposed while a
  /// rule still listens to it.
  void _coordinate() {
    // The app side of the desktop seam, registered first so it stops reading
    // the controllers before any of them goes away.
    desktopSurface = _register(
      FlucordAppSurface(
        chat: chat,
        workspace: workspace,
        onProtocolUri: (uri) => unawaited(oauth.handleProtocolUri(uri)),
      ),
    );
    sessionCoordination = ChatSessionCoordination(
      chat: chat,
      voice: voice,
      directCall: directCall,
      streamRtc: streamRtc,
      userSettings: userSettings,
      userProfile: userProfile,
      soundboardPlayback: soundboardPlayback,
      goLive: goLive,
      selfPresence: selfPresence,
    );
    _teardown.add(sessionCoordination.dispose);
    voiceRoomCoordination = VoiceRoomCoordination(
      voice: voice,
      remoteCameras: remoteCameras,
      overlay: voiceOverlay,
      streamerMode: streamerMode,
      goLive: goLive,
    );
    _teardown.add(voiceRoomCoordination.dispose);
    accountCoordination = AccountConnectionCoordination(
      oauth: oauth,
      accountConnection: accountConnection,
      socialSdk: socialSdk,
      directory: oauthGuildDirectory,
      membership: oauthGuildMembership,
      friends: discordFriends,
      socialDm: socialDm,
      socialPresence: socialPresence,
      socialActivity: socialActivity,
    );
    _teardown.add(accountCoordination.dispose);
    developerCheck = DeveloperCheck(chat: chat, voice: voice, goLive: goLive);
    _teardown.add(developerCheck.dispose);
  }

  /// Wires the app into the machine and starts the session flows, once the
  /// widget is live: everything here needs a binding or touches the screen.
  void start() {
    // R07's non-embedded fallback marks the account active on real input.
    // The handler always answers false so that every key still reaches the
    // widget that was going to receive it.
    ServicesBinding.instance.keyboard.addHandler(_markActiveOnKey);
    // Installed on the keyboard rather than in a Shortcuts widget: a
    // binding has to fire wherever the focus is, including the composer.
    ServicesBinding.instance.keyboard.addHandler(keybinds.handleKeyEvent);
    bootstrap.desktopIntegration?.attach(desktopSurface);
    connection.initialize(
      restoreSavedSession: bootstrap.restoreSavedSession && !_demo,
    );
    oauth.initialize();
    socialSdk.initialize();
  }

  /// Tears the graph down in reverse construction order: whatever reads
  /// another part dies before it. Parts received from outside
  /// ([AppBootstrap.desktopIntegration], [AppBootstrap.voiceMessageRecorder])
  /// keep their old places at the ends of the sequence.
  void dispose() {
    unawaited(bootstrap.desktopIntegration?.dispose());
    ServicesBinding.instance.keyboard.removeHandler(_markActiveOnKey);
    ServicesBinding.instance.keyboard.removeHandler(keybinds.handleKeyEvent);
    for (final dispose in _teardown.reversed) {
      dispose();
    }
    unawaited(bootstrap.voiceMessageRecorder?.dispose());
  }

  bool _markActiveOnKey(KeyEvent event) {
    selfPresence.markActive();
    return false;
  }

  /// The hook this platform has, or one that plainly says it has none.
  static GlobalKeyboardHook _defaultKeyboardHook() => Platform.isWindows
      ? WindowsGlobalKeyboardHook()
      : const UnavailableGlobalKeyboardHook();

  /// The shield this platform has, or one that plainly says it has none.
  static WindowCaptureShield _defaultCaptureShield() => Platform.isWindows
      ? WindowsWindowCaptureShield()
      : const UnavailableWindowCaptureShield();

  /// Records a constructed part for reverse-order teardown.
  T _register<T extends ChangeNotifier>(T controller) {
    _teardown.add(controller.dispose);
    return controller;
  }
}
