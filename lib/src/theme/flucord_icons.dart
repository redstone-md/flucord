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
  // The voice and user panels.
  static const micOff = FlucordIconData(HugeIcons.strokeRoundedMicOff01);
  static const headphonesOff = FlucordIconData(
    HugeIcons.strokeRoundedHeadphoneOff,
  );
  static const cameraOff = FlucordIconData(HugeIcons.strokeRoundedVideoOff);
  static const screenShareOff = FlucordIconData(
    HugeIcons.strokeRoundedScreenShareOff,
    matchTextDirection: true,
  );
  static const activities = FlucordIconData(HugeIcons.strokeRoundedRocket01);
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
  // The chat header and the composer.
  static const call = FlucordIconData(HugeIcons.strokeRoundedCall02);
  static const channels = FlucordIconData(HugeIcons.strokeRoundedMenu01);
  static const attach = FlucordIconData(HugeIcons.strokeRoundedAddCircle);
  static const upload = FlucordIconData(HugeIcons.strokeRoundedFileUpload);
  static const poll = FlucordIconData(HugeIcons.strokeRoundedChartBarLine);
  static const gif = FlucordIconData(HugeIcons.strokeRoundedGif01);
  static const sticker = FlucordIconData(HugeIcons.strokeRoundedSticker);
  static const send = FlucordIconData(
    HugeIcons.strokeRoundedSent,
    matchTextDirection: true,
  );
  static const slowmode = FlucordIconData(HugeIcons.strokeRoundedTimer02);
  static const readOnly = FlucordIconData(HugeIcons.strokeRoundedUnavailable);
  static const explore = FlucordIconData(HugeIcons.strokeRoundedDiscoverCircle);
  static const more = FlucordIconData(HugeIcons.strokeRoundedMoreHorizontal);
  // Hugeicons' plain "signal" is the messenger logo; these are the bars.
  static const signal = FlucordIconData(HugeIcons.strokeRoundedSignalFull02);
  static const mention = FlucordIconData(HugeIcons.strokeRoundedAt);
  static const mail = FlucordIconData(HugeIcons.strokeRoundedMail01);
  static const lightTheme = FlucordIconData(HugeIcons.strokeRoundedSun03);
  static const darkTheme = FlucordIconData(HugeIcons.strokeRoundedMoon02);
  static const person = FlucordIconData(HugeIcons.strokeRoundedUser);
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

  // The channel list and its voice seats.
  static const forum = FlucordIconData(HugeIcons.strokeRoundedBubbleChat);

  // Activity kinds, as a member row shows them.
  static const game = FlucordIconData(HugeIcons.strokeRoundedGameController03);
  static const streaming = FlucordIconData(
    HugeIcons.strokeRoundedLiveStreaming02,
  );
  static const listening = FlucordIconData(HugeIcons.strokeRoundedMusicNote01);
  static const watching = FlucordIconData(HugeIcons.strokeRoundedTv01);
  static const competing = FlucordIconData(HugeIcons.strokeRoundedChampion);

  // Voice, threads, forums and events (FLUCORD-84).
  static const event = FlucordIconData(HugeIcons.strokeRoundedCalendar03);
  static const eventUnavailable = FlucordIconData(
    HugeIcons.strokeRoundedCalendarRemove01,
  );
  static const archive = FlucordIconData(HugeIcons.strokeRoundedArchive);
  static const filterOff = FlucordIconData(HugeIcons.strokeRoundedFilterRemove);
  static const newPost = FlucordIconData(HugeIcons.strokeRoundedCommentAdd01);
  static const raiseHand = FlucordIconData(HugeIcons.strokeRoundedHand);
  static const voiceCall = FlucordIconData(HugeIcons.strokeRoundedHeadset);
  static const speaking = FlucordIconData(HugeIcons.strokeRoundedAudioWave01);

  // Accounts, connection and status (FLUCORD-84).
  static const syncing = FlucordIconData(HugeIcons.strokeRoundedReload);
  static const credential = FlucordIconData(HugeIcons.strokeRoundedKey01);
  static const desktop = FlucordIconData(HugeIcons.strokeRoundedComputer);
  static const packageMissing = FlucordIconData(
    HugeIcons.strokeRoundedPackageRemove,
  );
  static const visible = FlucordIconData(HugeIcons.strokeRoundedView);
  static const hidden = FlucordIconData(HugeIcons.strokeRoundedViewOff);
  static const code = FlucordIconData(HugeIcons.strokeRoundedSourceCode);
  static const payment = FlucordIconData(HugeIcons.strokeRoundedCreditCard);
  static const website = FlucordIconData(HugeIcons.strokeRoundedGlobe02);
  static const openExternal = FlucordIconData(
    HugeIcons.strokeRoundedLinkSquare02,
    matchTextDirection: true,
  );
  static const authorized = FlucordIconData(
    HugeIcons.strokeRoundedSecurityCheck,
  );
  static const chevronUp = FlucordIconData(HugeIcons.strokeRoundedArrowUp01);
  static const server = FlucordIconData(HugeIcons.strokeRoundedServerStack01);
  static const qrCode = FlucordIconData(HugeIcons.strokeRoundedQrCode);
  static const phone = FlucordIconData(HugeIcons.strokeRoundedSmartPhone01);
  static const bot = FlucordIconData(HugeIcons.strokeRoundedRobot01);
  static const warning = FlucordIconData(HugeIcons.strokeRoundedAlert02);
  static const back = FlucordIconData(
    HugeIcons.strokeRoundedArrowLeft02,
    matchTextDirection: true,
  );
  static const caughtUp = FlucordIconData(HugeIcons.strokeRoundedMailOpen01);
  static const summary = FlucordIconData(HugeIcons.strokeRoundedSparkles);

  // Messages and pickers (FLUCORD-84).
  static const chevronLeft = FlucordIconData(
    HugeIcons.strokeRoundedArrowLeft01,
    matchTextDirection: true,
  );
  static const jumpUp = FlucordIconData(HugeIcons.strokeRoundedArrowUp02);
  static const jumpDown = FlucordIconData(HugeIcons.strokeRoundedArrowDown02);
  static const joined = FlucordIconData(
    HugeIcons.strokeRoundedLogin01,
    matchTextDirection: true,
  );
  static const minus = FlucordIconData(HugeIcons.strokeRoundedMinusSign);
  static const noResults = FlucordIconData(HugeIcons.strokeRoundedSearchRemove);
  static const findPerson = FlucordIconData(
    HugeIcons.strokeRoundedUserSearch01,
  );
  static const mediaChannel = FlucordIconData(HugeIcons.strokeRoundedAlbum02);
  static const sort = FlucordIconData(HugeIcons.strokeRoundedSortByDown02);
  static const attachment = FlucordIconData(
    HugeIcons.strokeRoundedAttachment01,
  );
  static const dateBefore = FlucordIconData(HugeIcons.strokeRoundedCalendar03);
  static const dateAfter = FlucordIconData(HugeIcons.strokeRoundedClock01);
  static const pending = FlucordIconData(HugeIcons.strokeRoundedHourglass);
  static const file = FlucordIconData(HugeIcons.strokeRoundedFile01);
  static const videoFile = FlucordIconData(HugeIcons.strokeRoundedFileVideo);
  static const brokenImage = FlucordIconData(
    HugeIcons.strokeRoundedImageNotFound01,
  );
  static const play = FlucordIconData(HugeIcons.strokeRoundedPlay);
  static const pause = FlucordIconData(HugeIcons.strokeRoundedPause);
  static const volume = FlucordIconData(HugeIcons.strokeRoundedVolumeHigh);
  static const volumeOff = FlucordIconData(HugeIcons.strokeRoundedVolumeOff);
  static const fullscreen = FlucordIconData(HugeIcons.strokeRoundedFullScreen);
  static const exitFullscreen = FlucordIconData(
    HugeIcons.strokeRoundedMinimizeScreen,
  );
  static const audio = FlucordIconData(HugeIcons.strokeRoundedAudioWave01);
  static const superReaction = FlucordIconData(HugeIcons.strokeRoundedSparkles);
  static const favourite = FlucordIconData(HugeIcons.strokeRoundedStar);
  // System messages.
  static const boost = FlucordIconData(HugeIcons.strokeRoundedFlash);
  static const stage = FlucordIconData(HugeIcons.strokeRoundedPodcast);
  static const stop = FlucordIconData(HugeIcons.strokeRoundedStopCircle);
  static const alertMode = FlucordIconData(HugeIcons.strokeRoundedShieldAlert);
  static const alertModeOff = FlucordIconData(HugeIcons.strokeRoundedShieldOff);
  static const reportOff = FlucordIconData(HugeIcons.strokeRoundedFlagOff);
  // Emoji picker categories.
  static const recent = FlucordIconData(HugeIcons.strokeRoundedHistory);
  static const emojiAnimals = FlucordIconData(HugeIcons.strokeRoundedPawPrint);
  static const emojiFood = FlucordIconData(HugeIcons.strokeRoundedRestaurant01);
  static const emojiTravel = FlucordIconData(
    HugeIcons.strokeRoundedAirplaneTakeOff01,
  );
  static const emojiActivities = FlucordIconData(
    HugeIcons.strokeRoundedPartyPopper,
  );
  static const emojiObjects = FlucordIconData(HugeIcons.strokeRoundedBulb);
  static const emojiSymbols = FlucordIconData(HugeIcons.strokeRoundedFavourite);
  static const emojiFlags = FlucordIconData(HugeIcons.strokeRoundedFlag02);
}

/// Draws a [FlucordIcons] entry at the design's 1.75 stroke on the 24 grid.
///
/// Size and colour come from the ambient [IconTheme] unless given here, so it
/// drops in where an [Icon] was. Like [Icon], it keeps its size and centres
/// when a parent forces a larger box on it.
class FlucordIcon extends StatelessWidget {
  const FlucordIcon(this.icon, {super.key, this.size, this.color});

  static const double _strokeWidth = 1.75;

  final FlucordIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final size = this.size ?? IconTheme.of(context).size;
    final drawing = HugeIcon(
      icon: icon.data,
      size: size,
      color: color,
      strokeWidth: _strokeWidth,
    );
    final mirror =
        icon.matchTextDirection &&
        Directionality.of(context) == TextDirection.rtl;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: mirror ? Transform.flip(flipX: true, child: drawing) : drawing,
      ),
    );
  }
}
