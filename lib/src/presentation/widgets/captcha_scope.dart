import 'package:flutter/widgets.dart';

import '../../domain/discord_remote_auth.dart';
import 'discord_hcaptcha_panel.dart';

/// Builds the view that solves [challenge] and hands the key to [onSolved].
typedef CaptchaBuilder =
    Widget Function(
      DiscordRemoteAuthCaptchaChallenge challenge,
      Future<void> Function(String key) onSolved,
    );

/// The app's captcha view: hCaptcha in WebView2.
Widget hcaptchaPanel(
  DiscordRemoteAuthCaptchaChallenge challenge,
  Future<void> Function(String key) onSolved,
) => DiscordHcaptchaPanel(
  key: ValueKey(challenge.rqToken ?? challenge.rqData ?? challenge.siteKey),
  challenge: challenge,
  onSolved: onSolved,
);

/// Which captcha view every surface that meets a captcha shows: sign-in and
/// friend requests alike. A test hands in its own, since WebView2 does not
/// run there.
class CaptchaScope extends InheritedWidget {
  const CaptchaScope({required this.builder, required super.child, super.key});

  final CaptchaBuilder builder;

  /// The nearest scope's builder, or [hcaptchaPanel] outside any scope.
  static CaptchaBuilder of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CaptchaScope>()?.builder ??
      hcaptchaPanel;

  @override
  bool updateShouldNotify(CaptchaScope oldWidget) =>
      builder != oldWidget.builder;
}
