part of 'guild_settings_controller.dart';

extension GuildSettingsControllerWebhooks on GuildSettingsController {
  /// Creates a webhook pointing at [draft.channelId], then reloads the list
  /// rather than splicing the answer in: the server mints an id and may
  /// normalise the name, and a row this window invented would disagree with
  /// the next honest load.
  Future<bool> createWebhook(GuildWebhookDraft draft) async {
    if (!_capabilities.canManageWebhooks) return false;
    return _run(() async {
      await _repository.createWebhook(guildId: guildId, draft: draft);
      _webhooks = await _repository.loadWebhooks(guildId);
    });
  }

  Future<bool> saveWebhook({
    required String webhookId,
    required GuildWebhookEdit edit,
  }) async {
    if (!_capabilities.canManageWebhooks || edit.isEmpty) return false;
    return _run(() async {
      final updated = await _repository.updateWebhook(
        webhookId: webhookId,
        edit: edit,
      );
      _webhooks = [
        for (final webhook in _webhooks)
          webhook.id == webhookId ? updated : webhook,
      ];
    });
  }

  Future<bool> deleteWebhook(String webhookId) async {
    if (!_capabilities.canManageWebhooks) return false;
    return _run(() async {
      await _repository.deleteWebhook(webhookId);
      _webhooks = [
        for (final webhook in _webhooks)
          if (webhook.id != webhookId) webhook,
      ];
    });
  }
}
