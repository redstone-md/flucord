import 'package:flutter/widgets.dart';

import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/room_focus.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/attachment_download_scope.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flucord/src/presentation/widgets/direct_call_scope.dart';
import 'package:flucord/src/presentation/widgets/expression_favorites_scope.dart';
import 'package:flucord/src/presentation/widgets/external_link_launcher_scope.dart';
import 'package:flucord/src/presentation/widgets/gif_picker_scope.dart';
import 'package:flucord/src/presentation/widgets/go_live_scope.dart';
import 'package:flucord/src/presentation/widgets/message_component_scope.dart';
import 'package:flucord/src/presentation/widgets/remote_camera_scope.dart';
import 'package:flucord/src/presentation/widgets/room_focus_scope.dart';
import 'package:flucord/src/presentation/widgets/slash_command_scope.dart';
import 'package:flucord/src/presentation/widgets/soundboard_scope.dart';
import 'package:flucord/src/presentation/widgets/stage_scope.dart';
import 'package:flucord/src/presentation/widgets/stream_viewer_scope.dart';
import 'package:flucord/src/presentation/widgets/thread_membership_scope.dart';
import 'package:flucord/src/presentation/widgets/voice_message_recorder_scope.dart';
import 'package:flucord/src/presentation/widgets/voice_scope.dart';
import 'package:flucord/src/presentation/widgets/workspace_scope.dart';

/// The scope nest the app builds above the pane, so a test exercises the pane
/// exactly as production wires it.
///
/// The four controllers a room's stream controls read can be swapped. Anything
/// left out comes from [composition], which is what a test that does not care
/// about streams wants; a test that does care passes its own and reads back
/// what was asked for.
Widget paneHarness(
  AppComposition composition,
  ChatWorkspace workspace, {
  required ConversationChannel channel,
  ChannelCapabilities capabilities = ChannelCapabilities.unrestricted,
  VoiceController? voice,
  DirectCallController? directCall,
  GoLiveController? goLive,
  StreamViewerController? streamViewer,
  RoomFocus? focus,
}) => RoomFocusScope(
  focus: focus ?? composition.roomFocus,
  child: ChatScope(
    controller: composition.chat,
    child: WorkspaceScope(
      controller: composition.workspace,
      child: DirectCallScope(
        controller: directCall ?? composition.directCall,
        child: ExternalLinkLauncherScope(
          launcher: composition.externalLinkLauncher,
          child: AttachmentDownloadScope(
            service: composition.attachmentDownload,
            child: VoiceMessageRecorderScope(
              recorder: composition.voiceMessageRecorder,
              child: ThreadMembershipScope(
                controller: composition.threadMembership,
                child: StageScope(
                  controller: composition.stage,
                  child: SoundboardScope(
                    controller: composition.soundboard,
                    child: GoLiveScope(
                      controller: goLive ?? composition.goLive,
                      child: StreamViewerScope(
                        controller: streamViewer ?? composition.streamViewer,
                        child: RemoteCameraScope(
                          controller: composition.remoteCameras,
                          child: GifPickerScope(
                            controller: composition.gifPicker,
                            child: ExpressionFavoritesScope(
                              controller: composition.expressionFavorites,
                              child: SlashCommandScope(
                                controller: composition.slashCommand,
                                child: MessageComponentScope(
                                  controller: composition.messageComponent,
                                  child: VoiceScope(
                                    controller: voice ?? composition.voice,
                                    child: ConversationPane(
                                      workspace: workspace,
                                      capabilities: capabilities,
                                      channel: channel,
                                      channels: WorkspacePermissions(
                                        workspace,
                                      ).visibleChannelsFor(channel.spaceId),
                                      compact: false,
                                      allowMemberPanel: true,
                                      allowThreadPanel: true,
                                      showMembers: false,
                                      showPins: false,
                                      showThreads: false,
                                      onPickChannel: (_) {},
                                      onSelectChannel: (_) {},
                                      onOpenInbox: () {},
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
