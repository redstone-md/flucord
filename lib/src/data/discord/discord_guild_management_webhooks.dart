part of 'discord_guild_management_repository.dart';

/// The webhook routes.
///
/// A webhook's url embeds its token, so the payloads are read down to the
/// fields the settings window shows; anything else the server sends back is
/// left where it arrived.
mixin _DiscordGuildWebhooks {
  DiscordRestClient get _rest;

  Future<List<GuildWebhook>> loadWebhooks(String guildId) async => [
    for (final payload in await _rest.getList(
      '/guilds/${_segment(guildId)}/webhooks',
    ))
      if (DiscordGuildAdminMapper.webhook(payload, guildId)
          case final GuildWebhook webhook)
        webhook,
  ];

  Future<GuildWebhook> createWebhook({
    required String guildId,
    required GuildWebhookDraft draft,
  }) async {
    final payload = await _rest.requestObject(
      'POST',
      '/guilds/${_segment(guildId)}/webhooks',
      body: draft.toJson(),
    );
    return DiscordGuildAdminMapper.webhook(payload, guildId)!;
  }

  Future<GuildWebhook> updateWebhook({
    required String webhookId,
    required GuildWebhookEdit edit,
  }) async {
    final payload = await _rest.requestObject(
      'PATCH',
      '/webhooks/${_segment(webhookId)}',
      body: edit.toJson(),
    );
    return DiscordGuildAdminMapper.webhook(payload, '')!;
  }

  Future<void> deleteWebhook(String webhookId) =>
      _rest.requestEmpty('DELETE', '/webhooks/${_segment(webhookId)}');
}
