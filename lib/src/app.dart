import 'dart:async';

import 'package:flutter/material.dart';

import 'application/voice_channel_surface.dart';
import 'app_bootstrap.dart';
import 'app_composition.dart';
import 'presentation/flucord_shell.dart';
import 'presentation/widgets/accessibility_scope.dart';
import 'presentation/widgets/spell_check_scope.dart';
import 'presentation/widgets/attachment_download_scope.dart';
import 'presentation/widgets/chat_scope.dart';
import 'presentation/widgets/guild_access_scope.dart';
import 'presentation/widgets/join_server_dialog.dart';
import 'presentation/widgets/discord_account_connection_scope.dart';
import 'presentation/widgets/discord_desktop_login_scope.dart';
import 'presentation/widgets/discord_friends_scope.dart';
import 'presentation/widgets/discord_social_dm_navigation_scope.dart';
import 'presentation/widgets/discord_social_dm_scope.dart';
import 'presentation/widgets/discord_social_activity_scope.dart';
import 'presentation/widgets/discord_social_presence_scope.dart';
import 'presentation/widgets/discord_social_sdk_scope.dart';
import 'presentation/widgets/direct_call_scope.dart';
import 'presentation/widgets/expression_favorites_scope.dart';
import 'presentation/widgets/external_link_launcher_scope.dart';
import 'presentation/widgets/gif_picker_scope.dart';
import 'presentation/widgets/go_live_scope.dart';
import 'presentation/widgets/message_component_scope.dart';
import 'presentation/widgets/remote_camera_scope.dart';
import 'presentation/widgets/self_presence_scope.dart';
import 'presentation/widgets/slash_command_scope.dart';
import 'presentation/widgets/soundboard_scope.dart';
import 'presentation/widgets/stage_scope.dart';
import 'presentation/widgets/room_focus_scope.dart';
import 'presentation/widgets/stream_viewer_scope.dart';
import 'presentation/widgets/thread_membership_scope.dart';
import 'presentation/widgets/voice_message_recorder_scope.dart';
import 'presentation/widgets/workspace_scope.dart';
import 'presentation/widgets/account_standing_scope.dart';
import 'presentation/widgets/auth_session_scope.dart';
import 'presentation/widgets/account_connections_scope.dart';
import 'presentation/widgets/account_data_package_scope.dart';
import 'presentation/widgets/account_entitlements_scope.dart';
import 'presentation/widgets/app_authorisation_scope.dart';
import 'presentation/widgets/age_verification_scope.dart';
import 'presentation/widgets/multi_factor_auth_scope.dart';
import 'presentation/widgets/keybind_scope.dart';
import 'presentation/widgets/stream_quality_scope.dart';
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
        _composition.accessibility,
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
        home: Builder(
          builder: (context) {
            final accessibility = _composition.accessibility;
            return AccessibilityScope(
              controller: accessibility,
              child: SpellCheckScope(
                service: _composition.spellCheck,
                // The dials apply through the MediaQuery the whole tree
                // already reads, so every widget honours them without being
                // threaded through constructors. Zoom is a transform: the
                // interface lays out at its scaled size rather than being
                // painted small and stretched.
                child: Transform.scale(
                  scale: accessibility.zoom,
                  alignment: Alignment.topLeft,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(accessibility.fontScale),
                      disableAnimations: accessibility.reducesMotion,
                    ),
                    child: AccountDataPackageScope(
                      controller: _composition.accountDataPackage,
                      child: SelfPresenceScope(
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
                                    child: AccountConnectionsScope(
                                      controller:
                                          _composition.accountConnections,
                                      child: AccountEntitlementsScope(
                                        controller:
                                            _composition.accountEntitlements,
                                        child: AppAuthorisationScope(
                                          controller:
                                              _composition.appAuthorisation,
                                          child: ThemeScope(
                                            controller: _composition.theme,
                                            child: VoiceScope(
                                              controller: _composition.voice,
                                              child: StreamerModeScope(
                                                controller:
                                                    _composition.streamerMode,
                                                child: StreamQualityScope(
                                                  controller: _composition
                                                      .streamQuality,
                                                  child: KeybindScope(
                                                    controller:
                                                        _composition.keybinds,
                                                    child: UserSettingsScope(
                                                      controller: _composition
                                                          .userSettings,
                                                      child: DiscordDesktopLoginScope(
                                                        controller: _composition
                                                            .desktopLogin,
                                                        child: DiscordAccountConnectionScope(
                                                          controller: _composition
                                                              .accountConnection,
                                                          child: DiscordSocialSdkScope(
                                                            controller:
                                                                _composition
                                                                    .socialSdk,
                                                            child: DiscordSocialActivityScope(
                                                              controller:
                                                                  _composition
                                                                      .socialActivity,
                                                              child: DiscordSocialPresenceScope(
                                                                controller:
                                                                    _composition
                                                                        .socialPresence,
                                                                child: DiscordSocialDmNavigationScope(
                                                                  controller:
                                                                      _composition
                                                                          .socialDmNavigation,
                                                                  child: DiscordSocialDmScope(
                                                                    controller:
                                                                        _composition
                                                                            .socialDm,
                                                                    child: DiscordFriendsScope(
                                                                      controller:
                                                                          _composition
                                                                              .discordFriends,
                                                                      child: _conversationScopes(
                                                                        FlucordShell(
                                                                          chatController:
                                                                              _composition.chat,
                                                                          connectionController:
                                                                              _composition.connection,
                                                                          discordOAuthController:
                                                                              _composition.oauth,
                                                                          oauthGuildDirectoryController:
                                                                              _composition.oauthGuildDirectory,
                                                                          oauthGuildMembershipController:
                                                                              _composition.oauthGuildMembership,
                                                                          workspaceController:
                                                                              _composition.workspace,
                                                                          memberListController:
                                                                              _composition.memberList,
                                                                          memberProfileController:
                                                                              _composition.memberProfile,
                                                                          messageSearchController:
                                                                              _composition.messageSearch,
                                                                          voiceController:
                                                                              _composition.voice,
                                                                          selfVideoController:
                                                                              _composition.selfVideo,
                                                                          directCallController:
                                                                              _composition.directCall,
                                                                          externalLinkLauncher:
                                                                              _composition.externalLinkLauncher,
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
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The theme to draw with, built from whichever palette is in force.
  ThemeData _installedTheme({required bool dark}) => FlucordTheme.fromPalette(
    _composition.theme.paletteFor(systemIsDark: dark),
  );

  /// Wraps the shell in the scopes the conversation pane resolves its
  /// controllers from.
  ///
  /// One wrap per controller, following the scope modules that already serve
  /// the settings window: adding a conversation feature means adding its
  /// scope here and reading it in the pane, with no constructor in between
  /// changing shape.
  Widget _conversationScopes(Widget child) => GuildAccessScope(
    onOpenInvite: (context, code) => unawaited(
      showJoinServerDialog(context, chat: _composition.chat, code: code),
    ),
    onOpenMessageLink: (context, link) {
      // The workspace is read here rather than captured, because the shell
      // below may outlive a session that replaced it.
      final workspace = _composition.chat.workspace;
      if (workspace == null) return;
      final channel = workspace.channelOrNull(link.channelId);
      if (channel == null || channel.spaceId != link.spaceId) return;
      _composition.workspace.selectSpace(workspace, link.spaceId);
      if (link.messageId != null) {
        _composition.workspace.selectMessage(link.channelId, link.messageId!);
      } else {
        _composition.workspace.selectChannel(
          link.channelId,
          surface: VoiceChannelSurface.chat,
        );
      }
      unawaited(
        _composition.chat.openChannel(
          link.channelId,
          anchorMessageId: link.messageId,
        ),
      );
    },
    child: ChatScope(
      controller: _composition.chat,
      child: WorkspaceScope(
        controller: _composition.workspace,
        child: DirectCallScope(
          controller: _composition.directCall,
          child: ExternalLinkLauncherScope(
            launcher: _composition.externalLinkLauncher,
            child: AttachmentDownloadScope(
              service: _composition.attachmentDownload,
              child: VoiceMessageRecorderScope(
                recorder: _composition.voiceMessageRecorder,
                child: ThreadMembershipScope(
                  controller: _composition.threadMembership,
                  child: StageScope(
                    controller: _composition.stage,
                    child: SoundboardScope(
                      controller: _composition.soundboard,
                      child: GoLiveScope(
                        controller: _composition.goLive,
                        child: StreamViewerScope(
                          controller: _composition.streamViewer,
                          child: RoomFocusScope(
                            focus: _composition.roomFocus,
                            child: RemoteCameraScope(
                              controller: _composition.remoteCameras,
                              child: GifPickerScope(
                                controller: _composition.gifPicker,
                                child: ExpressionFavoritesScope(
                                  controller: _composition.expressionFavorites,
                                  child: SlashCommandScope(
                                    controller: _composition.slashCommand,
                                    child: MessageComponentScope(
                                      controller: _composition.messageComponent,
                                      child: child,
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
