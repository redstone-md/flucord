import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_desktop_login_controller.dart';
import '../../theme/flucord_theme.dart';
import 'developer_bot_transport_section.dart';
import 'discord_desktop_login_section.dart';

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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.surfaces.border),
      ),
      backgroundColor: context.surfaces.raised,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListenableBuilder(
            listenable: desktopLoginController,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogHeader(onClose: () => Navigator.of(context).pop()),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DiscordDesktopLoginSection(
                          controller: desktopLoginController,
                          connectionController: controller,
                        ),
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
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Connections',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }
}
