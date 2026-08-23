import 'package:flutter/material.dart';

import 'app_bootstrap.dart';
import 'app_composition.dart';
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
import 'theme/flucord_theme.dart';

/// The application widget.
///
/// It owns nothing but the composition's lifetime: construction,
/// coordination and disposal live in [AppComposition], reached through the
/// [AppBootstrap] seam. This widget subscribes to the few controllers the
/// chrome follows and builds the scope tree over the composition's fields.
class FlucordApp extends StatefulWidget {
  const FlucordApp({this.bootstrap = const AppBootstrap(), super.key});

  /// The demo preset: deterministic workspace data, no saved session.
  factory FlucordApp.demo() => FlucordApp(bootstrap: AppBootstrap.demo());

  final AppBootstrap bootstrap;

  @override
  State<FlucordApp> createState() => _FlucordAppState();
}

class _FlucordAppState extends State<FlucordApp> {
  late final AppComposition _composition;

  @override
  void initState() {
    super.initState();
    _composition = AppComposition(widget.bootstrap);
    _composition.start();
  }

  @override
  void dispose() {
    _composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _composition.workspace,
        _composition.userSettings,
        _composition.selfPresence,
        _composition.theme,
      ]),
      builder: (context, _) => MaterialApp(
        scaffoldMessengerKey: _composition.messengerKey,
        title: 'Flucord',
        debugShowCheckedModeBanner: false,
        // An installed theme carries its own light-or-dark answer, so it is
        // given to both slots: somebody who chose a dark theme did not ask
        // for it to turn pale when the account's setting says light.
        theme: _installedTheme(dark: false),
        darkTheme: _installedTheme(dark: true),
        // The account's theme wins whenever it names one Flucord can draw;
        // the rail's toggle stays usable for sessions that have no account
        // behind them, and for a stored theme Flucord does not ship.
        themeMode:
            _composition.userSettings.themeMode ??
            _composition.workspace.themeMode,
        home: SelfPresenceScope(
          controller: _composition.selfPresence,
          child: UserProfileScope(
            controller: _composition.userProfile,
            child: AccountStandingScope(
              controller: _composition.accountStanding,
              child: FamilyCentreScope(
                controller: _composition.familyCentre,
                child: AuthSessionScope(
                  controller: _composition.authSession,
                  child: MultiFactorAuthScope(
                    controller: _composition.multiFactorAuth,
                    child: AgeVerificationScope(
                      controller: _composition.ageVerification,
                      child: ThemeScope(
                        controller: _composition.theme,
                        child: VoiceScope(
                          controller: _composition.voice,
                          child: StreamerModeScope(
                            controller: _composition.streamerMode,
                            child: KeybindScope(
                              controller: _composition.keybinds,
                              child: UserSettingsScope(
                                controller: _composition.userSettings,
                                child: DiscordDesktopLoginScope(
                                  controller: _composition.desktopLogin,
                                  child: DiscordAccountConnectionScope(
                                    controller: _composition.accountConnection,
                                    child: DiscordSocialSdkScope(
                                      controller: _composition.socialSdk,
                                      child: DiscordSocialActivityScope(
                                        controller: _composition.socialActivity,
                                        child: DiscordSocialPresenceScope(
                                          controller:
                                              _composition.socialPresence,
                                          child: DiscordSocialDmNavigationScope(
                                            controller:
                                                _composition.socialDmNavigation,
                                            child: DiscordSocialDmScope(
                                              controller: _composition.socialDm,
                                              child: DiscordFriendsScope(
                                                controller:
                                                    _composition.discordFriends,
                                                child: FlucordShell(
                                                  chatController:
                                                      _composition.chat,
                                                  connectionController:
                                                      _composition.connection,
                                                  discordOAuthController:
                                                      _composition.oauth,
                                                  oauthGuildDirectoryController:
                                                      _composition
                                                          .oauthGuildDirectory,
                                                  oauthGuildMembershipController:
                                                      _composition
                                                          .oauthGuildMembership,
                                                  workspaceController:
                                                      _composition.workspace,
                                                  memberListController:
                                                      _composition.memberList,
                                                  messageSearchController:
                                                      _composition
                                                          .messageSearch,
                                                  voiceController:
                                                      _composition.voice,
                                                  threadMembershipController:
                                                      _composition
                                                          .threadMembership,
                                                  stageController:
                                                      _composition.stage,
                                                  soundboardController:
                                                      _composition.soundboard,
                                                  goLiveController:
                                                      _composition.goLive,
                                                  selfVideoController:
                                                      _composition.selfVideo,
                                                  remoteCameraController:
                                                      _composition
                                                          .remoteCameras,
                                                  streamViewerController:
                                                      _composition.streamViewer,
                                                  gifPickerController:
                                                      _composition.gifPicker,
                                                  expressionFavoritesController:
                                                      _composition
                                                          .expressionFavorites,
                                                  slashCommandController:
                                                      _composition.slashCommand,
                                                  messageComponentController:
                                                      _composition
                                                          .messageComponent,
                                                  directCallController:
                                                      _composition.directCall,
                                                  voiceMessageRecorder:
                                                      _composition
                                                          .voiceMessageRecorder,
                                                  attachmentDownloadService:
                                                      _composition
                                                          .attachmentDownload,
                                                  externalLinkLauncher:
                                                      _composition
                                                          .externalLinkLauncher,
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

  /// The theme to draw with, built from whichever palette is in force.
  ThemeData _installedTheme({required bool dark}) => FlucordTheme.fromPalette(
    _composition.theme.paletteFor(systemIsDark: dark),
  );
}
