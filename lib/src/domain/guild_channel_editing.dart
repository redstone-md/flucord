part of 'guild_management.dart';

/// The channel types the settings surface can create.
///
/// Deliberately not every type Discord numbers: a store, stage or directory
/// channel needs fields this client cannot fill (`sku_id` throws locally in the
/// renderer when missing), and offering a control that always fails is worse
/// than not offering it.
enum GuildChannelType implements GuildWireEnum {
  text(0),
  voice(2),
  category(4),
  announcement(5),
  forum(15);

  const GuildChannelType(this.wireValue);

  @override
  final int wireValue;

  static GuildChannelType? fromWire(Object? value) => _byWire(values, value);

  /// Whether this type lives in the text column of the channel list. The
  /// position pass runs per visual bucket, so this is what decides which bucket
  /// a channel is numbered within.
  bool get isTextLike => this == text || this == announcement || this == forum;

  bool get isVoiceLike => this == voice;
}

/// `POST /guilds/{id}/channels`.
final class GuildChannelDraft {
  const GuildChannelDraft({
    required this.type,
    required this.name,
    this.parentId,
    this.topic,
    this.bitrate,
    this.userLimit,
  });

  final GuildChannelType type;
  final String name;
  final String? parentId;
  final String? topic;
  final int? bitrate;
  final int? userLimit;

  /// Omissions here are the renderer's, not a simplification: `bitrate` is
  /// dropped when null, `user_limit` when null or not positive, and `parent_id`
  /// when null — sending `parent_id: null` explicitly would mean "move to the
  /// root", which is a different request from "create wherever you like".
  Map<String, Object?> toJson() => {
    'type': type.wireValue,
    'name': name,
    'permission_overwrites': const <Object?>[],
    if (topic != null && topic!.isNotEmpty) 'topic': topic,
    if (parentId != null) 'parent_id': parentId,
    if (bitrate != null) 'bitrate': bitrate,
    if (userLimit != null && userLimit! > 0) 'user_limit': userLimit,
  };
}

/// A partial `PATCH /channels/{id}`.
final class GuildChannelEdit {
  GuildChannelEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;
  set topic(String? value) => _values['topic'] = value;
  set nsfw(bool value) => _values['nsfw'] = value;
  set bitrate(int value) => _values['bitrate'] = value;
  set userLimit(int value) => _values['user_limit'] = value;
  set parentId(String? value) => _values['parent_id'] = value;

  /// Slowmode, in seconds. Discord's own control tops out at six hours and the
  /// server rejects anything above it, so the bound is enforced here rather
  /// than letting the request fail.
  set rateLimitPerUser(int value) {
    if (value < 0 || value > 21600) {
      throw ArgumentError.value(
        value,
        'rateLimitPerUser',
        'Slowmode runs from 0 to 21600 seconds',
      );
    }
    _values['rate_limit_per_user'] = value;
  }

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(_values);
}

/// One entry of the sparse array `PATCH /guilds/{id}/channels` takes.
///
/// Sparse is the whole point. `parent_id: null` moves a channel to the root and
/// omitting the key leaves its category alone, so a delta that always emitted
/// every field would un-categorise half a guild on the first drag.
final class ChannelPositionDelta {
  const ChannelPositionDelta({
    required this.id,
    this.position,
    this.parentId,
    this.hasParentId = false,
    this.lockPermissions = false,
  });

  final String id;
  final int? position;
  final String? parentId;

  /// Whether [parentId] is meant at all. Without this a null parent could not
  /// be told apart from an untouched one.
  final bool hasParentId;

  /// Sent only for the channel the user actually dragged, and only when they
  /// confirmed syncing permissions with the new category.
  final bool lockPermissions;

  ChannelPositionDelta withParent(String? value) => ChannelPositionDelta(
    id: id,
    position: position,
    parentId: value,
    hasParentId: true,
    lockPermissions: lockPermissions,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (position != null) 'position': position,
    if (hasParentId) 'parent_id': parentId,
    if (lockPermissions) 'lock_permissions': true,
  };

  @override
  bool operator ==(Object other) =>
      other is ChannelPositionDelta &&
      other.id == id &&
      other.position == position &&
      other.parentId == parentId &&
      other.hasParentId == hasParentId &&
      other.lockPermissions == lockPermissions;

  @override
  int get hashCode =>
      Object.hash(id, position, parentId, hasParentId, lockPermissions);

  @override
  String toString() =>
      'ChannelPositionDelta($id, position: $position, '
      'parent: ${hasParentId ? parentId : '<kept>'})';
}

/// What the channel reorder pass needs to know about one channel.
final class ChannelOrderEntry {
  const ChannelOrderEntry({
    required this.id,
    required this.position,
    required this.type,
    this.parentId,
  });

  final String id;
  final int position;
  final GuildChannelType type;
  final String? parentId;
}

/// Turns a reordered channel list into the sparse deltas Discord expects.
///
/// The renderer runs the delta pass three times — categories, text-like
/// channels, voice-like channels — and concatenates the results, because
/// Discord numbers each of those columns from zero independently. Running one
/// pass over the merged list would renumber every text channel by however many
/// voice channels sit above it, which the server accepts and the sidebar then
/// renders in an order nobody chose.
///
/// [movedChannelId] with [newParentId] appends or merges the reparent, and
/// [lockPermissions] rides along on that one entry only.
List<ChannelPositionDelta> channelReorderDeltas({
  required List<ChannelOrderEntry> before,
  required List<ChannelOrderEntry> after,
  String? movedChannelId,
  String? newParentId,
  bool lockPermissions = false,
}) {
  final deltas = <ChannelPositionDelta>[];
  for (final bucket in _channelBuckets) {
    for (final delta in calculatePositionDeltas<ChannelOrderEntry>(
      oldOrdering: [
        for (final item in before)
          if (bucket(item)) item,
      ],
      newOrdering: [
        for (final item in after)
          if (bucket(item)) item,
      ],
      idOf: (item) => item.id,
      positionOf: (item) => item.position,
      ascending: true,
    )) {
      deltas.add(ChannelPositionDelta(id: delta.id, position: delta.position));
    }
  }
  if (movedChannelId == null) return List.unmodifiable(deltas);
  final index = deltas.indexWhere((delta) => delta.id == movedChannelId);
  final reparented =
      (index >= 0 ? deltas[index] : ChannelPositionDelta(id: movedChannelId))
          .withParent(newParentId);
  final entry = lockPermissions
      ? ChannelPositionDelta(
          id: reparented.id,
          position: reparented.position,
          parentId: reparented.parentId,
          hasParentId: true,
          lockPermissions: true,
        )
      : reparented;
  if (index >= 0) {
    deltas[index] = entry;
  } else {
    deltas.add(entry);
  }
  return List.unmodifiable(deltas);
}

const _channelBuckets = <bool Function(ChannelOrderEntry)>[
  _isCategory,
  _isTextLike,
  _isVoiceLike,
];

bool _isCategory(ChannelOrderEntry entry) =>
    entry.type == GuildChannelType.category;
bool _isTextLike(ChannelOrderEntry entry) => entry.type.isTextLike;
bool _isVoiceLike(ChannelOrderEntry entry) => entry.type.isVoiceLike;
