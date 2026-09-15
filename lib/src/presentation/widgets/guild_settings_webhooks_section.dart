import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import 'guild_settings_controls.dart';

/// The webhooks page: what exists, where each one posts, and the controls to
/// add, retarget and remove them.
///
/// Gated on MANAGE_WEBHOOKS as a whole: Discord gates the list itself on the
/// same bit, so a member without it would be loading a page the server refuses
/// to answer.
class GuildSettingsWebhooksSection extends StatefulWidget {
  const GuildSettingsWebhooksSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

  @override
  State<GuildSettingsWebhooksSection> createState() =>
      _GuildSettingsWebhooksSectionState();
}

class _GuildSettingsWebhooksSectionState
    extends State<GuildSettingsWebhooksSection> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final webhooks = controller.webhooks;
    return GuildSettingsPanel(
      title: 'Webhooks',
      subtitle: 'External services that post into this server.',
      trailing: FilledButton.tonal(
        key: const ValueKey('guild-webhook-create'),
        onPressed: controller.isBusy ? null : () => _create(context),
        child: const Text('New webhook'),
      ),
      children: [
        GuildSettingsActionError(error: controller.actionError),
        if (webhooks.isEmpty)
          const GuildSettingsEmpty(message: 'There are no webhooks yet.')
        else
          for (final webhook in webhooks)
            GuildSettingsRow(
              key: ValueKey('guild-webhook-${webhook.id}'),
              leading: const Icon(Icons.anchor, size: 16),
              title: webhook.name,
              subtitle: 'Posts into #${_channelName(webhook.channelId)}',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: ValueKey('guild-webhook-edit-${webhook.id}'),
                    onPressed: controller.isBusy
                        ? null
                        : () => _edit(context, webhook),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    key: ValueKey('guild-webhook-delete-${webhook.id}'),
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(controller.deleteWebhook(webhook.id)),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  String _channelName(String channelId) =>
      widget.workspace.channelOrNull(channelId)?.name ?? 'unknown channel';

  Future<void> _create(BuildContext context) async {
    final channels = _postableChannels();
    if (channels.isEmpty) return;
    final choice = await showDialog<({String channelId, String name})>(
      context: context,
      builder: (_) => _WebhookDialog(
        title: 'Create webhook',
        confirmLabel: 'Create',
        channels: channels,
        initialChannelId: channels.first.id,
      ),
    );
    if (choice == null) return;
    await widget.controller.createWebhook(
      GuildWebhookDraft(name: choice.name, channelId: choice.channelId),
    );
  }

  Future<void> _edit(BuildContext context, GuildWebhook webhook) async {
    final channels = _postableChannels();
    final edit = await showDialog<({String channelId, String name})>(
      context: context,
      builder: (_) => _WebhookDialog(
        title: 'Edit webhook',
        confirmLabel: 'Save',
        channels: channels,
        initialName: webhook.name,
        initialChannelId: channels.any((c) => c.id == webhook.channelId)
            ? webhook.channelId
            : (channels.isEmpty ? null : channels.first.id),
      ),
    );
    if (edit == null) return;
    final changes = GuildWebhookEdit();
    if (edit.name != webhook.name) changes.name = edit.name;
    if (edit.channelId != webhook.channelId) {
      changes.channelId = edit.channelId;
    }
    await widget.controller.saveWebhook(webhookId: webhook.id, edit: changes);
  }

  List<ConversationChannel> _postableChannels() => widget.workspace
      .channelsFor(widget.spaceId)
      .where(
        (channel) =>
            !channel.isThread &&
            (channel.kind == ChannelKind.text ||
                channel.kind == ChannelKind.voice),
      )
      .toList(growable: false);
}

class _WebhookDialog extends StatefulWidget {
  const _WebhookDialog({
    required this.title,
    required this.confirmLabel,
    required this.channels,
    this.initialName,
    this.initialChannelId,
  });

  final String title;
  final String confirmLabel;
  final List<ConversationChannel> channels;
  final String? initialName;
  final String? initialChannelId;

  @override
  State<_WebhookDialog> createState() => _WebhookDialogState();
}

class _WebhookDialogState extends State<_WebhookDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? '',
  );
  late String? _channelId = widget.initialChannelId ?? widget.channels.first.id;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('webhook-dialog'),
    title: Text(widget.title),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('webhook-name'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Webhook name',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('webhook-channel'),
            initialValue: _channelId,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final channel in widget.channels)
                DropdownMenuItem(value: channel.id, child: Text(channel.name)),
            ],
            onChanged: (value) => setState(() => _channelId = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('webhook-confirm'),
        onPressed: _name.text.trim().isEmpty || _channelId == null
            ? null
            : () => Navigator.of(
                context,
              ).pop((channelId: _channelId!, name: _name.text.trim())),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
