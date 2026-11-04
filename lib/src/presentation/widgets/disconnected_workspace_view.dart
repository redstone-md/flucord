import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_desktop_login_controller.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'discord_desktop_login_section.dart';

/// The screen with no session open. It is the sign-in screen, and after a
/// failed connection it also says why and offers a Retry.
final class DisconnectedWorkspaceView extends StatefulWidget {
  const DisconnectedWorkspaceView({
    required this.connection,
    required this.login,
    required this.onOpenConnections,
    super.key,
  });

  final ConnectionController connection;
  final DiscordDesktopLoginController login;
  final VoidCallback onOpenConnections;

  @override
  State<DisconnectedWorkspaceView> createState() =>
      _DisconnectedWorkspaceViewState();
}

final class _DisconnectedWorkspaceViewState
    extends State<DisconnectedWorkspaceView> {
  late final Listenable _signInChanges = Listenable.merge([
    widget.connection,
    widget.login,
  ]);

  /// The sign-in this screen started, while it is still opening. A sign-out
  /// sets the sign-in back to idle as its last step, which can land while this
  /// runs, and must not open a second one.
  Future<void>? _opening;

  @override
  void initState() {
    super.initState();
    _signInChanges.addListener(_offerSignIn);
    _offerSignIn();
  }

  @override
  void dispose() {
    _signInChanges.removeListener(_offerSignIn);
    super.dispose();
  }

  /// A new user gets the QR at once. Someone with a saved session gets Retry
  /// instead, and a sign-in that just failed keeps its error on screen.
  ///
  /// It runs again on each change of the connection or the sign-in, because a
  /// sign-out shows this screen before it has finished. The saved session goes
  /// last, once the files of the account are off the disk, and a QR sign-in
  /// only goes idle after that.
  void _offerSignIn() {
    if (_opening == null &&
        widget.connection.state == ConnectionActionState.idle &&
        !widget.connection.hasSavedCredential &&
        widget.login.state == DiscordDesktopLoginState.idle) {
      final opening = _opening = widget.login.start().whenComplete(
        () => _opening = null,
      );
      unawaited(opening);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListenableBuilder(
              listenable: widget.login,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A failed QR sign-in already shows this error in its section.
                  if (connection.state == ConnectionActionState.failure &&
                      connection.errorMessage != widget.login.errorMessage)
                    _ConnectionFailure(
                      reason: connection.errorMessage!,
                      detail: connection.errorDetail,
                      onRetry: connection.hasSavedCredential
                          ? () => unawaited(connection.connectSavedCredential())
                          : null,
                    ),
                  DiscordDesktopLoginSection(
                    controller: widget.login,
                    connectionController: connection,
                  ),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('open-disconnected-connections'),
                      onPressed: widget.onOpenConnections,
                      icon: const FlucordIcon(FlucordIcons.link, size: 16),
                      label: const Text('Connections'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ConnectionFailure extends StatelessWidget {
  const _ConnectionFailure({
    required this.reason,
    required this.detail,
    required this.onRetry,
  });

  final String reason;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          FlucordIcon(
            FlucordIcons.offline,
            size: 28,
            color: context.surfaces.warning,
          ),
          const SizedBox(height: 10),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: FlucordTextRole.label.strong,
          ),
          if (detail case final detail?) ...[
            const SizedBox(height: 4),
            SelectableText(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('disconnected-retry'),
              onPressed: onRetry,
              icon: const FlucordIcon(FlucordIcons.refresh, size: 17),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
