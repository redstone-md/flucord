import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_member_admin_controller.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_theme.dart';

/// The moderation block of a member popover: roles, nickname, timeout, kick
/// and ban.
///
/// Dumb on purpose: [GuildMemberAdminController] owns every permission answer
/// and every write, so this widget renders what it is told and never decides
/// who may be acted on. A controller that says there is nothing to do gets no
/// block at all, from the host.
class MemberModerationSection extends StatefulWidget {
  const MemberModerationSection({required this.controller, super.key});

  final GuildMemberAdminController controller;

  @override
  State<MemberModerationSection> createState() =>
      _MemberModerationSectionState();
}

class _MemberModerationSectionState extends State<MemberModerationSection> {
  late final TextEditingController _nickname = TextEditingController(
    text: widget.controller.profile?.nickname ?? '',
  );
  int _timeoutSeconds = MemberTimeoutChoices.seconds.first;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    unawaited(widget.controller.load());
  }

  void _onChanged() {
    if (!mounted) return;
    // The nickname field tracks the server's answer until the user types, so
    // a rename made on another device arrives here and shows.
    if (widget.controller.profile?.nickname != null && _nickname.text.isEmpty) {
      _nickname.text = widget.controller.profile!.nickname!;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.hasAnyAction) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.error != null)
          Padding(
            key: const ValueKey('member-moderation-error'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'That change was not saved.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        _rolesBlock(context),
        _nicknameBlock(context),
        _timeoutBlock(context),
        _removalBlock(context),
      ],
    );
  }

  Widget _rolesBlock(BuildContext context) {
    final controller = widget.controller;
    final roles = [
      for (final role in controller.roles)
        if (controller.canAssignRole(role)) role,
    ];
    if (roles.isEmpty) return const SizedBox.shrink();
    final held = controller.profile?.roleIds.toSet() ?? const <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BlockLabel('ROLES'),
        const SizedBox(height: 6),
        for (final role in roles)
          CheckboxListTile(
            key: ValueKey('member-role-${role.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(role.name, overflow: TextOverflow.ellipsis),
            value: held.contains(role.id),
            onChanged: controller.isBusy
                ? null
                : (checked) => unawaited(
                    checked ?? false
                        ? controller.grantRole(role)
                        : controller.revokeRole(role),
                  ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _nicknameBlock(BuildContext context) {
    final controller = widget.controller;
    if (!controller.capabilities.canRename(controller.userId)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BlockLabel('NICKNAME'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('member-nickname'),
                controller: _nickname,
                enabled: !controller.isBusy,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'No nickname',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Reset nickname',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.clear),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(controller.setNickname('')),
            ),
            IconButton(
              key: const ValueKey('member-nickname-save'),
              tooltip: 'Save nickname',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.check),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(controller.setNickname(_nickname.text)),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _timeoutBlock(BuildContext context) {
    final controller = widget.controller;
    final canTimeout = controller.capabilities.canTimeout(controller.userId);
    if (!canTimeout) return const SizedBox.shrink();
    final timedOut = controller.profile?.isTimedOutAt(DateTime.now()) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BlockLabel('TIMEOUT'),
        const SizedBox(height: 6),
        if (timedOut) ...[
          Text(
            'Timed out until ${_format(controller.profile!.timeoutUntil!)}',
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
          OutlinedButton(
            key: const ValueKey('member-timeout-lift'),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(controller.liftTimeout()),
            child: const Text('Remove timeout'),
          ),
        ] else ...[
          DropdownButtonFormField<int>(
            key: const ValueKey('member-timeout-length'),
            initialValue: _timeoutSeconds,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final seconds in MemberTimeoutChoices.seconds)
                DropdownMenuItem(
                  value: seconds,
                  child: Text(MemberTimeoutChoices.label(seconds)),
                ),
            ],
            onChanged: controller.isBusy
                ? null
                : (value) => setState(
                    () => _timeoutSeconds = value ?? _timeoutSeconds,
                  ),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const ValueKey('member-timeout-apply'),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(
                    controller.timeoutMember(
                      Duration(seconds: _timeoutSeconds),
                    ),
                  ),
            child: const Text('Time out'),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _removalBlock(BuildContext context) {
    final controller = widget.controller;
    final canKick = controller.capabilities.canKick(controller.userId);
    final canBan = controller.capabilities.canBan(controller.userId);
    if (!canKick && !canBan) return const SizedBox.shrink();
    return Row(
      children: [
        if (canKick)
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('member-kick'),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(_confirmKick(context)),
              child: const Text('Kick'),
            ),
          ),
        if (canKick && canBan) const SizedBox(width: 8),
        if (canBan)
          Expanded(
            child: FilledButton(
              key: const ValueKey('member-ban'),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(_confirmBan(context)),
              child: const Text('Ban'),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmKick(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('member-kick-dialog'),
        title: const Text('Kick this member?'),
        content: const Text('They can rejoin with a new invite.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('member-kick-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await widget.controller.kickMember();
  }

  Future<void> _confirmBan(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('member-ban-dialog'),
        title: const Text('Ban this member?'),
        content: const Text('They cannot rejoin until somebody lifts the ban.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('member-ban-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ban'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await widget.controller.banMember();
  }

  static String _format(DateTime until) {
    final local = until.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w700,
      color: context.surfaces.muted,
    ),
  );
}
