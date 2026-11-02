import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_desktop_login_controller.dart';
import '../../domain/discord_session.dart';
import '../../theme/flucord_theme.dart';
import 'destructive_confirmation.dart';
import 'discord_hcaptcha_panel.dart';

final class DiscordDesktopLoginSection extends StatelessWidget {
  const DiscordDesktopLoginSection({
    required this.controller,
    required this.connectionController,
    super.key,
  });

  final DiscordDesktopLoginController controller;
  final ConnectionController connectionController;

  @override
  Widget build(BuildContext context) {
    final connected =
        connectionController.activeSession is DiscordDesktopUserSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  connected ? 'Discord chat' : 'Sign in to Discord',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (connected)
                const _StateLabel(label: 'Connected', color: Color(0xff3ba55d)),
            ],
          ),
          const SizedBox(height: 14),
          if (connected)
            FilledButton.icon(
              onPressed: controller.isBusy ? null : () => _signOut(context),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            )
          else
            _DisconnectedContent(controller: controller),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Sign out of Discord?',
      message: 'You will have to scan a new QR code to sign back in.',
      confirmLabel: 'Sign out',
    );
    if (confirmed) await controller.disconnect();
  }
}

final class _DisconnectedContent extends StatelessWidget {
  const _DisconnectedContent({required this.controller});

  final DiscordDesktopLoginController controller;

  @override
  Widget build(BuildContext context) {
    final qrUri = controller.qrUri;
    final captcha = controller.captchaChallenge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (captcha != null) ...[
          DiscordHcaptchaPanel(
            key: ValueKey(captcha.rqToken ?? captcha.rqData ?? captcha.siteKey),
            challenge: captcha,
            onSolved: controller.submitCaptcha,
          ),
          const SizedBox(height: 14),
        ] else if (qrUri != null &&
            controller.state == DiscordDesktopLoginState.qrReady) ...[
          Center(
            child: Container(
              width: 228,
              height: 228,
              color: Colors.white,
              child: QrImageView(
                data: qrUri.toString(),
                version: QrVersions.auto,
                size: 228,
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.white,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                semanticsLabel: 'Discord sign-in QR code',
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _Caption('Scan this code with the Discord app on your phone.'),
        ],
        if (controller.pendingDisplayName case final displayName?)
          _PendingIdentity(displayName: displayName),
        if (controller.state == DiscordDesktopLoginState.scanned)
          const _Caption('Now confirm the sign-in on your phone.'),
        if (controller.state == DiscordDesktopLoginState.starting ||
            controller.state == DiscordDesktopLoginState.connecting)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        if (controller.errorMessage case final error?) ...[
          Text(
            error,
            style: const TextStyle(color: FlucordColors.danger, fontSize: 13),
          ),
          const SizedBox(height: 12),
        ],
        if (!controller.isBusy)
          FilledButton.icon(
            onPressed: controller.start,
            icon: const Icon(Icons.qr_code_2, size: 19),
            label: const Text('Sign in with QR code'),
          )
        else
          OutlinedButton.icon(
            onPressed: controller.cancel,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel'),
          ),
      ],
    );
  }
}

final class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.surfaces.muted, fontSize: 13),
    ),
  );
}

final class _PendingIdentity extends StatelessWidget {
  const _PendingIdentity({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.phone_android, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

final class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
