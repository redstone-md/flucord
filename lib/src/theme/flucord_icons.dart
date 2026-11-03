import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// One Hugeicons drawing, plus whether it points a way and so must mirror in
/// right-to-left text, as [IconData.matchTextDirection] does.
@immutable
final class FlucordIconData {
  const FlucordIconData(this.data, {this.matchTextDirection = false});

  /// The path data `HugeIcon` draws.
  final List<List<dynamic>> data;

  final bool matchTextDirection;
}

/// The app's icons, named by what they mean rather than by their shape.
///
/// Draw them with [FlucordIcon], as `FlucordIcon(FlucordIcons.reply)`.
abstract final class FlucordIcons {
  static const textChannel = FlucordIconData(HugeIcons.strokeRoundedHashtag);
  static const voiceChannel = FlucordIconData(
    HugeIcons.strokeRoundedVolumeHigh,
  );
  static const chevronDown = FlucordIconData(
    HugeIcons.strokeRoundedArrowDown01,
  );
  static const chevronRight = FlucordIconData(
    HugeIcons.strokeRoundedArrowRight01,
    matchTextDirection: true,
  );
  static const search = FlucordIconData(HugeIcons.strokeRoundedSearch01);
  static const inbox = FlucordIconData(HugeIcons.strokeRoundedInbox);
  static const pin = FlucordIconData(HugeIcons.strokeRoundedPin);
  static const members = FlucordIconData(HugeIcons.strokeRoundedUserGroup);
  static const threads = FlucordIconData(
    HugeIcons.strokeRoundedMessageMultiple01,
  );
  static const mic = FlucordIconData(HugeIcons.strokeRoundedMic01);
  static const headphones = FlucordIconData(HugeIcons.strokeRoundedHeadphones);
  static const settings = FlucordIconData(HugeIcons.strokeRoundedSettings01);
  static const camera = FlucordIconData(HugeIcons.strokeRoundedVideo01);
  static const screenShare = FlucordIconData(
    HugeIcons.strokeRoundedScreenShare,
    matchTextDirection: true,
  );
  static const hangUp = FlucordIconData(HugeIcons.strokeRoundedCallEnd01);
  static const add = FlucordIconData(HugeIcons.strokeRoundedAdd01);
  static const emoji = FlucordIconData(HugeIcons.strokeRoundedSmile);
  static const reply = FlucordIconData(
    HugeIcons.strokeRoundedArrowTurnBackward,
    matchTextDirection: true,
  );
  static const directMessages = FlucordIconData(
    HugeIcons.strokeRoundedMessage01,
  );
  static const image = FlucordIconData(HugeIcons.strokeRoundedImage01);
  static const explore = FlucordIconData(HugeIcons.strokeRoundedDiscoverCircle);
  static const more = FlucordIconData(HugeIcons.strokeRoundedMoreHorizontal);
  // Hugeicons' plain "signal" is the messenger logo; these are the bars.
  static const signal = FlucordIconData(HugeIcons.strokeRoundedSignalFull02);
  static const mention = FlucordIconData(HugeIcons.strokeRoundedAt);
  static const mail = FlucordIconData(HugeIcons.strokeRoundedMail01);
  // Menu and popover actions.
  static const edit = FlucordIconData(HugeIcons.strokeRoundedPencilEdit01);
  static const forward = FlucordIconData(
    HugeIcons.strokeRoundedArrowTurnForward,
    matchTextDirection: true,
  );
  static const markUnread = FlucordIconData(
    HugeIcons.strokeRoundedMessageNotification01,
  );
  static const copy = FlucordIconData(HugeIcons.strokeRoundedCopy01);
  static const link = FlucordIconData(HugeIcons.strokeRoundedLink01);
  static const id = FlucordIconData(HugeIcons.strokeRoundedId);
  static const delete = FlucordIconData(HugeIcons.strokeRoundedDelete02);
  static const check = FlucordIconData(HugeIcons.strokeRoundedTick02);
  static const clear = FlucordIconData(HugeIcons.strokeRoundedCancel01);
  static const report = FlucordIconData(HugeIcons.strokeRoundedFlag01);
  static const block = FlucordIconData(HugeIcons.strokeRoundedUserBlock01);
  static const verified = FlucordIconData(
    HugeIcons.strokeRoundedCheckmarkBadge01,
  );

  // The message toolbar.
  static const addReaction = FlucordIconData(HugeIcons.strokeRoundedSmilePlus);
  static const unpin = FlucordIconData(HugeIcons.strokeRoundedPinOff);
  static const unlink = FlucordIconData(HugeIcons.strokeRoundedUnlink01);
  static const done = FlucordIconData(HugeIcons.strokeRoundedTaskDone01);
  static const reopen = FlucordIconData(
    HugeIcons.strokeRoundedArrowReloadHorizontal,
  );
  static const deleteFlagged = FlucordIconData(HugeIcons.strokeRoundedDelete03);
  static const thumbsDown = FlucordIconData(HugeIcons.strokeRoundedThumbsDown);
  static const silent = FlucordIconData(
    HugeIcons.strokeRoundedNotificationOff01,
  );
  static const spoken = FlucordIconData(HugeIcons.strokeRoundedVoice);

  // Settings and dialogs.
  static const info = FlucordIconData(HugeIcons.strokeRoundedInformationCircle);
  static const error = FlucordIconData(HugeIcons.strokeRoundedAlertCircle);
  static const offline = FlucordIconData(HugeIcons.strokeRoundedCloudOff);
  static const lock = FlucordIconData(HugeIcons.strokeRoundedSquareLock02);
  static const logOut = FlucordIconData(
    HugeIcons.strokeRoundedLogout03,
    matchTextDirection: true,
  );

  // User settings pages.
  static const profile = FlucordIconData(HugeIcons.strokeRoundedUserCircle);
  static const appearance = FlucordIconData(HugeIcons.strokeRoundedPaintBoard);
  static const chat = FlucordIconData(HugeIcons.strokeRoundedComment01);
  static const notifications = FlucordIconData(
    HugeIcons.strokeRoundedNotification01,
  );
  static const privacy = FlucordIconData(HugeIcons.strokeRoundedShield01);
  static const standing = FlucordIconData(
    HugeIcons.strokeRoundedJusticeScale01,
  );
  static const family = FlucordIconData(HugeIcons.strokeRoundedUserMultiple02);
  static const devices = FlucordIconData(
    HugeIcons.strokeRoundedComputerPhoneSync,
  );
  static const entitlements = FlucordIconData(HugeIcons.strokeRoundedAward01);
  static const twoFactor = FlucordIconData(HugeIcons.strokeRoundedKey01);
  static const ageVerification = FlucordIconData(
    HugeIcons.strokeRoundedIdVerified,
  );
  static const apps = FlucordIconData(HugeIcons.strokeRoundedRobot01);
  static const download = FlucordIconData(HugeIcons.strokeRoundedDownload01);
  static const keyboard = FlucordIconData(HugeIcons.strokeRoundedKeyboard);
  static const streamerMode = FlucordIconData(HugeIcons.strokeRoundedTv01);
  static const accessibility = FlucordIconData(
    HugeIcons.strokeRoundedAccessibility,
  );
  static const themes = FlucordIconData(HugeIcons.strokeRoundedPaintBrush01);
  static const language = FlucordIconData(HugeIcons.strokeRoundedTranslate);

  // Friends.
  static const activityInvite = FlucordIconData(
    HugeIcons.strokeRoundedGameController03,
  );
  static const removeFriend = FlucordIconData(
    HugeIcons.strokeRoundedUserRemove01,
  );
  static const friends = FlucordIconData(HugeIcons.strokeRoundedUserMultiple);
  static const plugin = FlucordIconData(HugeIcons.strokeRoundedPlug01);

  // Settings lists and forms.
  static const moveUp = FlucordIconData(HugeIcons.strokeRoundedArrowUp01);
  static const moveDown = FlucordIconData(HugeIcons.strokeRoundedArrowDown01);
  static const refresh = FlucordIconData(HugeIcons.strokeRoundedRefresh);
  static const radioOn = FlucordIconData(HugeIcons.strokeRoundedRadioButton);
  static const radioOff = FlucordIconData(HugeIcons.strokeRoundedCircle);
  static const checkCircle = FlucordIconData(
    HugeIcons.strokeRoundedCheckmarkCircle02,
  );
  static const addCircle = FlucordIconData(HugeIcons.strokeRoundedAddCircle);
  static const removeCircle = FlucordIconData(
    HugeIcons.strokeRoundedRemoveCircle,
  );
  static const noColour = FlucordIconData(HugeIcons.strokeRoundedCircleOff);
  static const erase = FlucordIconData(HugeIcons.strokeRoundedEraser01);
  static const keyword = FlucordIconData(HugeIcons.strokeRoundedTextFont);
  static const filter = FlucordIconData(HugeIcons.strokeRoundedFilter);
  static const listRemove = FlucordIconData(HugeIcons.strokeRoundedNoteRemove);
  static const policy = FlucordIconData(HugeIcons.strokeRoundedPolicy);
  static const help = FlucordIconData(HugeIcons.strokeRoundedHelpCircle);
  static const music = FlucordIconData(HugeIcons.strokeRoundedMusicNote01);
  static const micOff = FlucordIconData(HugeIcons.strokeRoundedMicOff01);
  static const cameraOff = FlucordIconData(HugeIcons.strokeRoundedVideoOff);

  // Server settings pages.
  static const overview = FlucordIconData(
    HugeIcons.strokeRoundedDashboardSquare01,
  );
  static const roles = FlucordIconData(HugeIcons.strokeRoundedShield02);
  static const ban = FlucordIconData(HugeIcons.strokeRoundedHammer);
  static const automod = FlucordIconData(HugeIcons.strokeRoundedRobotic);
  static const invite = FlucordIconData(HugeIcons.strokeRoundedUserAdd01);
  static const webhooks = FlucordIconData(HugeIcons.strokeRoundedWebhook);
  static const expressions = FlucordIconData(HugeIcons.strokeRoundedSticker);
  static const auditLog = FlucordIconData(HugeIcons.strokeRoundedNote01);
}

/// Draws a [FlucordIcons] entry at the design's 1.75 stroke on the 24 grid.
///
/// Size and colour come from the ambient [IconTheme] unless given here, so it
/// drops in where an [Icon] was.
class FlucordIcon extends StatelessWidget {
  const FlucordIcon(this.icon, {super.key, this.size, this.color});

  static const double _strokeWidth = 1.75;

  final FlucordIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final drawing = HugeIcon(
      icon: icon.data,
      size: size ?? IconTheme.of(context).size,
      color: color,
      strokeWidth: _strokeWidth,
    );
    final mirror =
        icon.matchTextDirection &&
        Directionality.of(context) == TextDirection.rtl;
    return mirror ? Transform.flip(flipX: true, child: drawing) : drawing;
  }
}
