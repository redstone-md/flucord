part of 'discord_desktop_rest_protocol.dart';

/// The read-state and notification-settings half of the desktop REST surface
/// (R04).
///
/// Two of these routes are easy to render wrong, and both mistakes are silent:
/// the guild-scoped ack puts the read-state **type** before the entity id, and
/// the user-scoped one interpolates the numeric type straight into the path.
/// Building them here, once, is what keeps a caller from guessing the order.
abstract final class DiscordDesktopReadStateRequests {
  /// `POST /channels/{c}/messages/{m}/ack` with the mark-unread body.
  ///
  /// The same route, a different contract: `token`, `last_viewed` and `flags`
  /// are not sent at all, and [messageId] is the message the divider should sit
  /// *after*, not the one the user clicked.
  static DiscordDesktopRestRequest markUnread({
    required String channelId,
    required String messageId,
    int mentionCount = 0,
  }) {
    if (mentionCount < 0) {
      throw ArgumentError.value(
        mentionCount,
        'mentionCount',
        'Cannot be negative',
      );
    }
    return DiscordDesktopRestRequest(
      method: 'POST',
      path:
          '/channels/${_snowflake(channelId, 'channelId')}'
          '/messages/${_snowflake(messageId, 'messageId')}'
          '/ack',
      body: {'manual': true, 'mention_count': mentionCount},
    );
  }

  /// `POST /guilds/{g}/ack/{type}/{entity}` for the guild-scoped types.
  static DiscordDesktopRestRequest ackGuildEntity({
    required String guildId,
    required int readStateType,
    required String entityId,
  }) => DiscordDesktopRestRequest(
    method: 'POST',
    path:
        '/guilds/${_snowflake(guildId, 'guildId')}'
        '/ack/${_readStateType(readStateType)}'
        '/${_snowflake(entityId, 'entityId')}',
    body: const {},
  );

  /// `POST /users/@me/{type}/{entity}/ack` for the account-scoped types.
  static DiscordDesktopRestRequest ackUserEntity({
    required int readStateType,
    required String entityId,
  }) => DiscordDesktopRestRequest(
    method: 'POST',
    path:
        '/users/@me/${_readStateType(readStateType)}'
        '/${_snowflake(entityId, 'entityId')}/ack',
    body: const {},
  );

  /// `DELETE /channels/{c}/messages/ack` — forget a read state entirely.
  static DiscordDesktopRestRequest deleteReadState({
    required String channelId,
    required int readStateType,
  }) => DiscordDesktopRestRequest(
    method: 'DELETE',
    path:
        '/channels/${_snowflake(channelId, 'channelId')}'
        '/messages/ack',
    body: {
      'version': 2,
      'read_state_type': _checkedReadStateType(readStateType),
    },
  );

  /// `POST /channels/{c}/pins/ack` — the pin list has been looked at.
  static DiscordDesktopRestRequest ackPins(String channelId) =>
      DiscordDesktopRestRequest(
        method: 'POST',
        path:
            '/channels/${_snowflake(channelId, 'channelId')}'
            '/pins/ack',
      );

  /// `PATCH /users/@me/guilds/{g}/settings`, where `{g}` may be `@me`.
  static DiscordDesktopRestRequest guildNotificationSettings({
    required String guildId,
    required Map<String, Object?> settings,
  }) => DiscordDesktopRestRequest(
    method: 'PATCH',
    path: '/users/@me/guilds/${_guildKey(guildId)}/settings',
    body: Map.unmodifiable({...settings}),
  );

  /// `PATCH /users/@me/guilds/settings` — the route every real guild uses.
  ///
  /// Discord strips the literal `@favorites` key before sending, because that
  /// pseudo-guild is a client-side grouping the server would reject.
  static DiscordDesktopRestRequest bulkNotificationSettings(
    Map<String, Map<String, Object?>> guilds,
  ) => DiscordDesktopRestRequest(
    method: 'PATCH',
    path: '/users/@me/guilds/settings',
    body: {
      'guilds': Map.unmodifiable({
        for (final entry in guilds.entries)
          if (entry.key != favoritesGuildKey)
            _guildKey(entry.key): Map.unmodifiable({...entry.value}),
      }),
    },
  );

  /// `PATCH /users/@me/notification-settings` — the account-wide flag word.
  static DiscordDesktopRestRequest accountNotificationSettings(int flags) =>
      DiscordDesktopRestRequest(
        method: 'PATCH',
        path: '/users/@me/notification-settings',
        body: {'flags': flags},
      );

  /// Discord's key for direct messages in every settings route.
  static const directMessagesGuildKey = '@me';

  /// The client-side favourites grouping, which never reaches the server.
  static const favoritesGuildKey = '@favorites';

  static String _guildKey(String guildId) => guildId == directMessagesGuildKey
      ? directMessagesGuildKey
      : _snowflake(guildId, 'guildId');

  /// Read-state types are a closed 0–5 enum on the wire, and this value is
  /// interpolated into a path rather than sent as JSON, so an out-of-range
  /// number would silently address a route that does not exist.
  static String _readStateType(int value) => '${_checkedReadStateType(value)}';

  static int _checkedReadStateType(int value) {
    if (value < 0 || value > 5) {
      throw ArgumentError.value(value, 'readStateType', 'Expected 0-5');
    }
    return value;
  }
}
