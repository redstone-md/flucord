import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_desktop_login_controller.dart';
import '../../theme/flucord_theme.dart';
import 'developer_bot_transport_section.dart';
import 'discord_account_connection_scope.dart';
import 'discord_desktop_login_section.dart';
import 'oauth_connection_section.dart';
import 'flucord_dialog.dart';

class ConnectionDialog extends StatelessWidget {
  const ConnectionDialog({
    required this.controller,
    required this.desktopLoginController,
    super.key,
  });

  final ConnectionController controller;
  final DiscordDesktopLoginController desktopLoginController;

  @override
  Widget build(BuildContext context) {
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: FlucordDialogHeader(title: 'Connections'),
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
