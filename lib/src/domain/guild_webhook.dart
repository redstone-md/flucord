part of 'guild_management.dart';

/// One webhook of a guild, as `GET /guilds/{id}/webhooks` reports it.
///
/// A webhook is a url and a token somebody else may post with; the token is
/// deliberately not carried here. The settings surface only needs to name,
/// retarget and delete them, and a value this window never uses is a value
/// that can be copied out of it.
final class GuildWebhook {
  const GuildWebhook({
    required this.id,
    required this.guildId,
    required this.channelId,
    required this.name,
    this.type = GuildWebhookType.incoming,
  });

  final String id;
  final String guildId;

  /// The channel the webhook posts into, which is also the only field the
  /// edit route can move.
  final String channelId;
  final String name;
  final GuildWebhookType type;
}

/// The webhook kinds Discord numbers. Only [incoming] is ever offered: a
/// [follower] is created by the announcement-follow flow, not by a person, and
/// an unknown value stays unknown rather than guessing.
enum GuildWebhookType implements GuildWireEnum {
  incoming(1),
  follower(2);

  const GuildWebhookType(this.wireValue);

  @override
  final int wireValue;

  static GuildWebhookType? fromWire(Object? value) => _byWire(values, value);
}

/// `POST /guilds/{id}/webhooks`.
final class GuildWebhookDraft {
  const GuildWebhookDraft({required this.name, required this.channelId});

  final String name;
  final String channelId;

  Map<String, Object?> toJson() => {'name': name, 'channel_id': channelId};
}

/// A partial `PATCH /webhooks/{id}`.
///
/// Same tri-state discipline as [GuildRoleEdit]: omitted means untouched.
/// The channel is the one field an owner ever moves, and `name` is the one
/// they ever retype.
final class GuildWebhookEdit {
  GuildWebhookEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;
  set channelId(String value) => _values['channel_id'] = value;

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(_values);
}
