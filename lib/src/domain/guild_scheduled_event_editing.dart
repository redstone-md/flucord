part of 'chat_models.dart';

/// `POST /guilds/{id}/scheduled-events`.
///
/// A draft is a whole event, because Discord takes one: a create with half the
/// fields is refused rather than filled in with defaults.
final class GuildScheduledEventDraft {
  const GuildScheduledEventDraft({
    required this.name,
    required this.startTime,
    required this.entityType,
    this.description = '',
    this.endTime,
    this.channelId,
    this.location = '',
    this.coverImage,
  });

  final String name;
  final String description;

  /// When it starts, and — for an event held somewhere Discord does not host —
  /// when it ends. Discord requires the end for an external event and refuses
  /// it for one held in a channel.
  final DateTime startTime;
  final DateTime? endTime;

  final GuildScheduledEventEntityType entityType;

  /// The voice or stage channel it happens in. Null for an external event.
  final String? channelId;

  /// Where an external event happens, in words.
  final String location;

  /// The cover, as a `data:` URI. Null when there is none: Discord tells an
  /// absent cover from a cleared one, and so does this.
  final String? coverImage;

  bool get isExternal => entityType == GuildScheduledEventEntityType.external;

  /// Whether Discord would take this.
  ///
  /// Checked here rather than only in the form because the same draft reaches
  /// the server from the create dialog and from a duplicated event, and the
  /// second path has no form to check it.
  bool get isValid {
    if (name.trim().isEmpty) return false;
    if (entityType == GuildScheduledEventEntityType.unknown) return false;
    if (isExternal) {
      // An external event has to say where and when it ends; Discord has no
      // channel to infer either from.
      if (location.trim().isEmpty || endTime == null) return false;
      return endTime!.isAfter(startTime);
    }
    if (channelId == null || channelId!.isEmpty) return false;
    return endTime == null || endTime!.isAfter(startTime);
  }
}

/// `PATCH /guilds/{id}/scheduled-events/{event}`.
///
/// Only what was touched is sent, so an edit of the name cannot quietly move
/// the start time to whatever the form happened to be showing.
final class GuildScheduledEventEdit {
  GuildScheduledEventEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;

  /// Cleared with an empty string rather than omitted: Discord distinguishes
  /// "leave the description" from "there is no description now".
  set description(String value) => _values['description'] = value;

  set startTime(DateTime value) =>
      _values['scheduled_start_time'] = value.toUtc().toIso8601String();

  set endTime(DateTime? value) =>
      _values['scheduled_end_time'] = value?.toUtc().toIso8601String();

  set channelId(String? value) => _values['channel_id'] = value;

  set location(String value) =>
      _values['entity_metadata'] = {'location': value};

  /// A `data:` URI, or null to take the cover off. A CDN hash is refused for
  /// the reason the profile refuses one: the server has no use for the name it
  /// gave us, and sending it back would ask it to store its own filename.
  set coverImage(String? value) {
    if (value != null && !value.startsWith('data:')) {
      throw ArgumentError.value(
        value,
        'coverImage',
        'A cover is a data: URI or null',
      );
    }
    _values['image'] = value;
  }

  /// Ending or cancelling an event is a status change, not a delete.
  set status(GuildScheduledEventStatus value) =>
      _values['status'] = value.discordValue;

  Map<String, Object?> toJson() => Map.unmodifiable(_values);

  /// Discord's own privacy level. The only one a guild event can have, so it
  /// is written rather than offered as a choice nobody has.
  static const guildOnlyPrivacyLevel = 2;

  /// The create body, shared with the edit encoder for the fields they share.
  static Map<String, Object?> encodeDraft(GuildScheduledEventDraft draft) => {
    'name': draft.name.trim(),
    'description': draft.description,
    'privacy_level': guildOnlyPrivacyLevel,
    'scheduled_start_time': draft.startTime.toUtc().toIso8601String(),
    'scheduled_end_time': draft.endTime?.toUtc().toIso8601String(),
    'entity_type': draft.entityType.discordValue,
    'channel_id': draft.isExternal ? null : draft.channelId,
    'entity_metadata': draft.isExternal ? {'location': draft.location} : null,
    if (draft.coverImage != null) 'image': draft.coverImage,
  };
}
