import 'application/connection_controller.dart';
import 'domain/attachment_download.dart';
import 'domain/chat_repository.dart';
import 'domain/chat_repository_factory.dart';
import 'domain/credential_vault.dart';
import 'domain/discord_oauth.dart';
import 'domain/discord_remote_auth.dart';
import 'domain/discord_social_dm.dart';
import 'domain/discord_social_sdk.dart';
import 'domain/external_link_launcher.dart';
import 'domain/keybind.dart';
import 'domain/soundboard_playback.dart';
import 'domain/streamer_mode.dart';
import 'domain/video_decoder.dart';
import 'domain/video_encoder.dart';
import 'domain/voice_audio.dart';
import 'domain/voice_media.dart';
import 'domain/voice_message_recorder.dart';
import 'platform/desktop_integration.dart';
import 'platform/global_keyboard_hook.dart';
import 'platform/voice_overlay.dart';
import 'platform/window_capture_shield.dart';
import 'data/theme/file_theme_store.dart';
import 'data/video/clip_recorder.dart';
import 'data/video/screenshot_service.dart';

/// What the app is built from, and what a test replaces.
///
/// This is the composition root's seam: [AppComposition] reads a default
/// here for anything left null and wires the substitute in otherwise, so a
/// test fakes one leaf by naming it once instead of threading it through
/// the widget's constructor. The fields the app can live without (a demo
/// has no desktop integration) are nullable in the graph too, so null means
/// "absent", never "forgot to set".
class AppBootstrap {
  const AppBootstrap({
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
  });

  /// The demo preset: deterministic workspace data (resolved by the
  /// composition when [initialSessionMode] is [SessionMode.demo] and no
  /// repository was supplied), no saved session to restore, and no bot
  /// transport offered.
  factory AppBootstrap.demo() => AppBootstrap(
    initialSessionMode: SessionMode.demo,
    enableBotTransport: false,
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
}
