import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_desktop_login_controller.dart';
import '../../theme/flucord_theme.dart';
import 'developer_bot_transport_section.dart';
import 'discord_account_connection_scope.dart';
import 'discord_desktop_login_section.dart';
import 'oauth_connection_section.dart';
import 'flucord_dialog.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    required this.controller,
    required this.desktopLoginController,
    super.key,
  });

  final ConnectionController controller;
  final DiscordDesktopLoginController desktopLoginController;

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late DiscordDesktopLoginState _loginState =
      widget.desktopLoginController.state;

  @override
  void initState() {
    super.initState();
    widget.desktopLoginController.addListener(_closeOnSignIn);
  }

  @override
  void didUpdateWidget(ConnectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(
      oldWidget.desktopLoginController,
      widget.desktopLoginController,
    )) {
      return;
    }
    oldWidget.desktopLoginController.removeListener(_closeOnSignIn);
    widget.desktopLoginController.addListener(_closeOnSignIn);
    _loginState = widget.desktopLoginController.state;
  }

  @override
  void dispose() {
    widget.desktopLoginController.removeListener(_closeOnSignIn);
    super.dispose();
  }

  /// A QR sign-in that finishes while the dialog is open closes it: the
  /// account is what the user opened it for. A failed or cancelled sign-in
  /// never reaches `connected`, so the dialog stays with its error.
  void _closeOnSignIn() {
    final state = widget.desktopLoginController.state;
    final signedIn =
        state == DiscordDesktopLoginState.connected &&
        _loginState != DiscordDesktopLoginState.connected;
    _loginState = state;
    if (signedIn && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final desktopLoginController = widget.desktopLoginController;
    final maxHeight = MediaQuery.sizeOf(context).height - 48;
    return FlucordDialog.frame(
      maxWidth: 520,
      maxHeight: maxHeight,
      actions: const [FlucordDialogCancel(label: 'Close')],
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListenableBuilder(
          listenable: desktopLoginController,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  FlucordDialog.titleTop,
                  20,
                  12,
                ),
                child: const FlucordDialogHeader(title: 'Connections'),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DiscordDesktopLoginSection(
                        controller: desktopLoginController,
                        connectionController: controller,
                      ),
                      // The OAuth identity and the Social SDK grant, which
                      // are separate credentials from the desktop session
                      // above and belong on the same screen as it.
                      if (DiscordAccountConnectionScope.maybeOf(context)
                          case final account?) ...[
                        Divider(height: 1, color: context.surfaces.border),
                        ListenableBuilder(
                          listenable: account,
                          builder: (_, _) =>
                              OAuthConnectionSection(controller: account),
                        ),
                      ],
                      if (controller.botTransportEnabled) ...[
                        Divider(height: 1, color: context.surfaces.border),
                        DeveloperBotTransportSection(
                          controller: controller,
                          onSessionChanged: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
