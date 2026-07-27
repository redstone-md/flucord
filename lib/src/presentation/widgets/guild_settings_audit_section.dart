import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/guild_audit_log.dart';
import '../../theme/flucord_theme.dart';
import 'guild_settings_controls.dart';

/// The audit log: what happened, who did it, and when.
///
/// Entries arrive merged. Renaming twelve channels in one sitting is twelve
/// wire entries and one line here, which is the difference between a log a
/// moderator reads and one they scroll past.
class GuildSettingsAuditSection extends StatelessWidget {
  const GuildSettingsAuditSection({required this.controller, super.key});

  final GuildSettingsController controller;

  /// The actions worth a filter entry. The wire enum has eighty-odd members and
  /// most of them never occur in a guild that is not a bot platform; these are
  /// the ones a moderator comes to the log looking for.
  static const filterableActions = [
    AuditLogActionType.memberBanAdd,
    AuditLogActionType.memberBanRemove,
    AuditLogActionType.memberKick,
    AuditLogActionType.memberRoleUpdate,
    AuditLogActionType.memberUpdate,
    AuditLogActionType.channelCreate,
    AuditLogActionType.channelDelete,
    AuditLogActionType.channelUpdate,
    AuditLogActionType.roleCreate,
    AuditLogActionType.roleUpdate,
    AuditLogActionType.roleDelete,
    AuditLogActionType.inviteCreate,
    AuditLogActionType.inviteDelete,
    AuditLogActionType.messageDelete,
    AuditLogActionType.guildUpdate,
  ];

  @override
  Widget build(BuildContext context) {
    final records = controller.auditRecords;
    return GuildSettingsPanel(
      title: 'Audit log',
      subtitle: 'The last actions taken in this server.',
      trailing: SizedBox(
        width: 190,
        child: DropdownButtonFormField<AuditLogActionType?>(
          key: const ValueKey('audit-action-filter'),
          initialValue: controller.auditQuery.action,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            const DropdownMenuItem<AuditLogActionType?>(
              child: Text('All actions'),
            ),
            for (final action in filterableActions)
              DropdownMenuItem<AuditLogActionType?>(
                value: action,
                child: Text(
                  auditActionLabel(action),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) =>
              unawaited(controller.filterAuditLog(action: value)),
        ),
      ),
      children: [
        if (records.isEmpty)
          const GuildSettingsEmpty(message: 'Nothing has been logged yet.')
        else
          for (final record in records) _entry(context, record),
        if (controller.hasOlderAuditEntries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                key: const ValueKey('audit-load-more'),
                onPressed: controller.isLoading(GuildSettingsSection.auditLog)
                    ? null
                    : () => unawaited(controller.loadMoreAuditEntries()),
                child: const Text('Load more'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _entry(BuildContext context, AuditLogRecord record) {
    final head = record.head;
    final actor = head.userId == null
        ? 'Someone'
        : controller.auditUserNames[head.userId!] ?? 'Unknown member';
    final count = record.isMerged ? ' (x${record.count})' : '';
    return GuildSettingsRow(
      key: ValueKey('audit-entry-${head.id}'),
      leading: Icon(_iconFor(head.actionClass), size: 16),
      title: '$actor ${auditActionLabel(head.action)}$count',
      subtitle: _subtitle(record),
      trailing: Text(
        _formatTime(record.timestampStart),
        style: TextStyle(fontSize: 11, color: context.surfaces.muted),
      ),
    );
  }

  static String _subtitle(AuditLogRecord record) {
    final reason = record.head.reason;
    if (reason != null && reason.isNotEmpty) return reason;
    final changes = record.head.changes;
    if (changes.isEmpty) return 'No details recorded';
    return changes.map((change) => change.key).take(4).join(', ');
  }

  static IconData _iconFor(AuditLogActionClass value) => switch (value) {
    AuditLogActionClass.create => Icons.add_circle_outline,
    AuditLogActionClass.update => Icons.edit_outlined,
    AuditLogActionClass.delete => Icons.remove_circle_outline,
    AuditLogActionClass.other => Icons.circle_outlined,
  };

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}

/// A human sentence for one audit action.
///
/// Only the actions Flucord can meaningfully phrase get one; everything else
/// falls back to the wire name with its underscores softened, which is still
/// more use than a bare number.
String auditActionLabel(AuditLogActionType action) => switch (action) {
  AuditLogActionType.guildUpdate => 'updated the server',
  AuditLogActionType.channelCreate => 'created a channel',
  AuditLogActionType.channelUpdate => 'updated a channel',
  AuditLogActionType.channelDelete => 'deleted a channel',
  AuditLogActionType.memberKick => 'kicked a member',
  AuditLogActionType.memberPrune => 'pruned members',
  AuditLogActionType.memberBanAdd => 'banned a member',
  AuditLogActionType.memberBanRemove => 'unbanned a member',
  AuditLogActionType.memberUpdate => 'updated a member',
  AuditLogActionType.memberRoleUpdate => 'changed member roles',
  AuditLogActionType.roleCreate => 'created a role',
  AuditLogActionType.roleUpdate => 'updated a role',
  AuditLogActionType.roleDelete => 'deleted a role',
  AuditLogActionType.inviteCreate => 'created an invite',
  AuditLogActionType.inviteUpdate => 'updated an invite',
  AuditLogActionType.inviteDelete => 'revoked an invite',
  AuditLogActionType.messageDelete => 'deleted a message',
  AuditLogActionType.messageBulkDelete => 'bulk deleted messages',
  AuditLogActionType.messagePin => 'pinned a message',
  AuditLogActionType.messageUnpin => 'unpinned a message',
  _ =>
    action.name
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (match) => ' ${match[0]!.toLowerCase()}',
        )
        .trim(),
};
