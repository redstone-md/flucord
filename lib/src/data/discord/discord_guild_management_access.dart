part of 'discord_guild_management_repository.dart';

/// Join, create, leave: the server-access routes.
///
/// Joining must hydrate a server the session was not opened with, so the
/// routes here answer with a whole [JoinedGuild] rather than a bare id. The
/// refusal model is shared with the join surface: invalid, expired and
/// already-joined invites fold into one exception type with a message a user
/// can read, because a raw status code is not something anybody joins a
/// server by.
mixin _DiscordGuildAccess {
  DiscordRestClient get _rest;
  DiscordMapper get _mapper;

  void Function(JoinedGuild guild)? get onGuildGained;
  void Function(String guildId)? get onGuildLeft;

  /// `GET /invites/{code}?with_counts=true`.
  ///
  /// The counts are what the join surface shows next to the server's name, so
  /// they are asked for even though the invite's own validity does not depend
  /// on them.
  Future<InvitePreview> previewInvite(String code) async {
    try {
      final payload = await _rest.requestObject(
        'GET',
        '/invites/${_segment(code)}',
        query: const {'with_counts': 'true'},
      );
      final preview = DiscordGuildAdminMapper.invitePreview(payload);
      if (preview != null) return preview;
      throw _invalidInvite();
    } on DiscordApiException catch (error) {
      // The preview card names the refusal the same words the join does,
      // so an expired invite reads as expired before the click, not after.
      if (error.statusCode == 404) {
        final code = error.responsePayload?['code'];
        final expired =
            code == 1007 || error.message.toLowerCase().contains('expired');
        if (expired) {
          throw const GuildAccessException(
            refusal: GuildAccessRefusal.expired,
            message: 'This invite has expired.',
          );
        }
      }
      throw _invalidInvite();
    }
  }

  /// `POST /invites/{code}`, followed by the routes that fill the workspace.
  ///
  /// The POST answers a partial guild; the channels, roles, and this
  /// account's own membership come from the guild routes, which is exactly
  /// what the permission model needs to answer visibility questions before
  /// the user opens anything. An already-joined account is refused with a
  /// 403, which is the one refusal this route has its own message for.
  Future<JoinedGuild> joinGuild(String code) async {
    final payload = await _rest
        .requestObject('POST', '/invites/${_segment(code)}')
        .catchError((Object error) => throw _joinRefusal(error));
    final guild = await _hydrateGuild(guildIdOfInvite(payload));
    onGuildGained?.call(guild);
    return guild;
  }

  /// `POST /guilds` with a name, followed by the same hydration as a join.
  ///
  /// Discord creates the default channel set server-side, so the create
  /// answer needs the same follow-up reads a join does.
  Future<JoinedGuild> createGuild({required String name}) async {
    final trimmed = name.trim();
    final payload = await _rest.requestObject(
      'POST',
      '/guilds',
      body: {'name': trimmed},
    );
    final guild = await _hydrateGuild(guildIdOfInvite(payload));
    onGuildGained?.call(guild);
    return guild;
  }

  /// `DELETE /users/@me/guilds/{id}`.
  ///
  /// Owners cannot leave what they own, and Discord says so; that refusal is
  /// reported as a message rather than a fault in the client.
  Future<void> leaveGuild(String guildId) async {
    try {
      await _rest.requestEmpty(
        'DELETE',
        '/users/@me/guilds/${_segment(guildId)}',
      );
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 403) {
        throw GuildAccessException(
          refusal: GuildAccessRefusal.unknown,
          message: 'This server could not be left: ${error.message}',
        );
      }
      rethrow;
    }
    onGuildLeft?.call(guildId);
  }

  /// One hydration answer for a guild the session just gained.
  ///
  /// The guild object, its channels, its roles, and this account's own
  /// membership: the reads that make a joined server usable without a
  /// restart. The own-membership read may be refused without breaking the
  /// join, because a member the mapper never saw is a case the permission
  /// model already answers honestly.
  Future<JoinedGuild> _hydrateGuild(String guildId) async {
    final guild = await _rest.getObject('/guilds/${_segment(guildId)}');
    final channels = await _rest.getList(
      '/guilds/${_segment(guildId)}/channels',
    );
    final roles = await _rest.getList('/guilds/${_segment(guildId)}/roles');
    final membership = await _readOwnMembership(guildId, roles);
    return DiscordGuildAdminMapper.joinedGuild(
      guild: guild,
      channels: channels,
      roles: roles,
      mapper: _mapper,
      members: membership == null ? const [] : [membership],
    );
  }

  Future<Member?> _readOwnMembership(
    String guildId,
    List<Map<String, Object?>> roles,
  ) async {
    try {
      final member = await _rest.getObject(
        '/guilds/${_segment(guildId)}/members/@me',
      );
      return _mapper.guildMember(member, guildId, roles);
    } on DiscordApiException {
      return null;
    }
  }

  GuildAccessException _invalidInvite() => const GuildAccessException(
    refusal: GuildAccessRefusal.invalid,
    message: 'This invite is not valid. Check the code and try again.',
  );

  /// Folds the POST's refusals into the three answers a user can act on.
  GuildAccessException _joinRefusal(Object error) {
    if (error is! DiscordApiException) {
      return const GuildAccessException(
        refusal: GuildAccessRefusal.unknown,
        message: 'This server could not be joined. Try again in a moment.',
      );
    }
    final code = error.responsePayload?['code'];
    if (error.statusCode == 403 || code == 40002) {
      return const GuildAccessException(
        refusal: GuildAccessRefusal.alreadyJoined,
        message: 'You are already in this server.',
      );
    }
    if (error.statusCode == 404) {
      final expired =
          code == 1007 || error.message.toLowerCase().contains('expired');
      return expired
          ? const GuildAccessException(
              refusal: GuildAccessRefusal.expired,
              message: 'This invite has expired.',
            )
          : const GuildAccessException(
              refusal: GuildAccessRefusal.invalid,
              message:
                  'This invite is not valid. Check the code and try '
                  'again.',
            );
    }
    return GuildAccessException(
      refusal: GuildAccessRefusal.unknown,
      message: 'This server could not be joined: ${error.message}',
    );
  }
}
