import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

/// The Lucide stroke weight the app draws with. Weight 300 is a 1.5 stroke on
/// Lucide's 24 px grid, the closest to the design's 1.75. Changing the weight
/// is this one line.
typedef _Lucide = LucideIcons300;

/// The app's icons, named by what they mean rather than by their shape.
///
/// Use them as `Icon(FlucordIcons.reply)`. Icons that point a way mirror in
/// right-to-left text, as their Material versions do.
abstract final class FlucordIcons {
  static const IconData textChannel = _Lucide.hash;
  static const IconData voiceChannel = _Lucide.volume2;
  static const IconData chevronDown = _Lucide.chevronDown;
  static const IconData chevronRight = _Lucide.chevronRightDir;
  static const IconData search = _Lucide.search;
  static const IconData inbox = _Lucide.inbox;
  static const IconData pin = _Lucide.pin;
  static const IconData members = _Lucide.users;
  static const IconData threads = _Lucide.messagesSquare;
  static const IconData mic = _Lucide.mic;
  static const IconData headphones = _Lucide.headphones;
  static const IconData settings = _Lucide.settings;
  static const IconData camera = _Lucide.video;
  static const IconData screenShare = _Lucide.screenShareDir;
  static const IconData hangUp = _Lucide.phoneOff;
  static const IconData add = _Lucide.plus;
  static const IconData emoji = _Lucide.smile;
  static const IconData reply = _Lucide.replyDir;
  static const IconData directMessages = _Lucide.messageCircle;
  static const IconData image = _Lucide.image;
  static const IconData explore = _Lucide.compass;
  static const IconData more = _Lucide.ellipsis;
  static const IconData signal = _Lucide.signal;
  static const IconData mention = _Lucide.atSign;
  static const IconData mail = _Lucide.mail;
}
