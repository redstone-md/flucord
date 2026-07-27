part of 'discord_guild_management_repository.dart';

/// Channel create, edit, delete and the position batch.
mixin _DiscordGuildChannelAdministration {
  DiscordRestClient get _rest;
  DiscordMapper get _mapper;

  Future<ConversationChannel> createGuildChannel({
    required String guildId,
    required GuildChannelDraft draft,
  }) async => _projectChannel(
    await _rest.requestObject(
      'POST',
      '/guilds/${_segment(guildId)}/channels',
      body: draft.toJson(),
    ),
    guildId,
  );

  Future<ConversationChannel> editGuildChannel({
    required String channelId,
    required GuildChannelEdit edit,
  }) async {
    final payload = await _rest.requestObject(
      'PATCH',
      '/channels/${_segment(channelId)}',
      body: edit.toJson(),
    );
    return _projectChannel(payload, payload['guild_id'] as String? ?? '');
  }

  Future<void> deleteGuildChannel(String channelId) =>
      _rest.requestEmpty('DELETE', '/channels/${_segment(channelId)}');

  /// One sparse array for the whole drag, the way the renderer sends it.
  Future<void> reorderGuildChannels({
    required String guildId,
    required List<ChannelPositionDelta> deltas,
  }) async {
    if (deltas.isEmpty) return;
    await _rest.requestJsonArray(
      'PATCH',
      '/guilds/${_segment(guildId)}/channels',
      body: [for (final delta in deltas) delta.toJson()],
    );
  }

  /// The shared channel mapper answers `null` for a category, because a
  /// category is not something the sidebar can open. Creating one is a
  /// first-class action on this surface, so the response is projected by hand
  /// rather than returned as "nothing happened" over a channel the server did
  /// create.
  ConversationChannel _projectChannel(
    Map<String, Object?> payload,
    String guildId,
  ) =>
      _mapper.channel(payload, guildId) ??
      ConversationChannel(
        id: payload['id'] as String? ?? '',
        spaceId: guildId,
        name: payload['name'] as String? ?? 'unnamed',
        topic: payload['topic'] as String? ?? '',
        kind: ChannelKind.text,
        position: payload['position'] as int? ?? 0,
        parentId: payload['parent_id'] as String?,
      );
}
