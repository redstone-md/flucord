import '../domain/channel_link.dart';
import '../domain/chat_models.dart';
import '../domain/voice_call.dart';
import '../platform/desktop_integration.dart';

/// What the desktop announces for [call] while the window is not in front.
///
/// [hidesNames] is streamer mode's: the toast lands on top of whatever is
/// being broadcast, so it says only that someone is calling. [showsToast] is
/// the account's and streamer mode's answer on toasts at all.
DesktopRingingCall ringingCallNotice(
  IncomingCall call,
  ChatWorkspace? workspace, {
  required bool hidesNames,
  required bool showsToast,
}) {
  final caller = hidesNames
      ? null
      : workspace?.memberOrNull(call.callerId)?.displayName;
  // A group DM the client has never opened still rings, and is still a DM.
  final spaceId =
      workspace?.channelOrNull(call.channelId)?.spaceId ??
      CommunitySpace.directMessagesId;
  return DesktopRingingCall(
    identifier: 'flucord-call-${call.channelId}',
    title: 'Incoming call',
    body: '${caller ?? 'Someone'} is calling',
    link: ChannelLink(spaceId: spaceId, channelId: call.channelId),
    showsToast: showsToast,
  );
}
