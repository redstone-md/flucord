import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'member_avatar.dart';
import 'flucord_icon_button.dart';
import 'streamer_mode_scope.dart';
import 'self_presence_scope.dart';
import 'self_status_menu.dart';
import 'user_settings_dialog.dart';
import 'user_settings_scope.dart';
import 'voice_control.dart';
import 'voice_scope.dart';

/// The account's own corner at the foot of the channel sidebar: who is signed
/// in, their status, and the mute, deafen and settings buttons.
class AccountPanel extends StatelessWidget {
  const AccountPanel({
    required this.member,
    required this.sessionMode,
    required this.connectionStatus,
    super.key,
  });

  final Member member;
  final SessionMode sessionMode;
  final RepositoryConnectionStatus connectionStatus;

  /// The panel's height at the default text size. Larger text grows it.
  static const height = 52.0;

  static const _buttonSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final presence = SelfPresenceScope.maybeOf(context);
    final voice = VoiceScope.maybeOf(context);
    final settings = UserSettingsScope.maybeOf(context);
    final broadcasting = presence?.isAvailable ?? false;
    final (status, color, tooltip) = _connectionLabels(context);
    // The account's own row is composed locally, so the panel prefers what
    // this client is broadcasting over whatever the member table last cached.
    final self = broadcasting
        ? presence!.userPresence
        : member.presenceOrCoarse;
    final custom = ActivitySummary.of([?self.customStatus]);
    final identity = Row(
      children: [
        MemberAvatar(
          member: member.withPresence(self),
          livePresence: false,
          size: 32,
          decorated: true,
          presenceBorderColor: context.surfaces.rail,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Blanked rather than truncated: the panel is in the corner of
                // every frame of a stream, and a name half shown is still a
                // name shown.
                StreamerModeScope.hidesPersonalInformation(context)
                    ? 'Hidden'
                    : member.displayName,
                key: const ValueKey('account-panel-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(
                  color: context.surfaces.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // The connection's state rides on the status line: the panel
              // has no mark of its own for it.
              Tooltip(
                message: tooltip,
                child: custom != null
                    ? ActivitySummaryLine(
                        key: const ValueKey('account-custom-status'),
                        summary: custom,
                        color: context.surfaces.captionText,
                      )
                    : Text(
                        broadcasting ? self.displayStatus.label : status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlucordTextRole.caption.style.copyWith(
                          color: broadcasting
                              ? context.surfaces.captionText
                              : color,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('account-panel'),
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: presence == null || !presence.isAvailable
                ? identity
                : SelfStatusMenu(controller: presence, child: identity),
          ),
          if (voice != null) ...[
            FlucordIconButton.control(
              key: const ValueKey('account-mute'),
              control: VoiceControl.mute(voice),
              dimension: _buttonSize,
            ),
            FlucordIconButton.control(
              key: const ValueKey('account-deafen'),
              control: VoiceControl.deafen(voice),
              dimension: _buttonSize,
            ),
          ],
          if (settings != null)
            FlucordIconButton(
              key: const ValueKey('account-settings'),
              tooltip: 'User settings',
              icon: FlucordIcons.settings,
              dimension: _buttonSize,
              onPressed: () => unawaited(
                UserSettingsDialog.showFromScopes(
                  context,
                  controller: settings,
                ),
              ),
            ),
        ],
      ),
    );
  }

  (String, Color, String) _connectionLabels(BuildContext context) =>
      switch (sessionMode) {
        SessionMode.disconnected => (
          'Disconnected',
          context.surfaces.captionText,
          'Not connected to Discord',
        ),
        SessionMode.demo => (
          'Demo workspace',
          Theme.of(context).colorScheme.primary,
          'Sample data, not your account',
        ),
        SessionMode.discord => switch (connectionStatus) {
          RepositoryConnectionStatus.connected => (
            'Discord online',
            context.surfaces.success,
            'Connected to Discord',
          ),
          RepositoryConnectionStatus.connecting => (
            'Connecting...',
            context.surfaces.warning,
            'Connecting to Discord',
          ),
          RepositoryConnectionStatus.reconnecting => (
            'Reconnecting...',
            context.surfaces.warning,
            'Reconnecting to Discord',
          ),
          RepositoryConnectionStatus.offline => (
            'Offline',
            context.surfaces.captionText,
            'Not connected to Discord',
          ),
        },
      };
}
