part 'guild_ban.dart';
part 'guild_channel_editing.dart';
part 'guild_invite.dart';
part 'guild_position_deltas.dart';
part 'guild_role_editing.dart';

/// The shared shape of every guild enum Discord numbers on the wire.
abstract interface class GuildWireEnum {
  int get wireValue;
}

/// Discord's `verification_level`.
enum GuildVerificationLevel implements GuildWireEnum {
  none(0),
  low(1),
  medium(2),
  high(3),
  veryHigh(4);

  const GuildVerificationLevel(this.wireValue);

  @override
  final int wireValue;

  /// The level [value] names, or `null` when Discord sent one this client has
  /// no name for.
  ///
  /// Null rather than a fallback member on purpose: the guild patch is partial,
  /// so an unrecognised level simply stays unsent and the server keeps whatever
  /// it had. Collapsing it into [none] would let opening the settings window
  /// and saving an unrelated field silently drop a guild's verification.
  static GuildVerificationLevel? fromWire(Object? value) =>
      _byWire(values, value);
}

/// Discord's `explicit_content_filter`.
enum GuildExplicitContentFilter implements GuildWireEnum {
  disabled(0),
  membersWithoutRoles(1),
  allMembers(2);

  const GuildExplicitContentFilter(this.wireValue);

  @override
  final int wireValue;

  static GuildExplicitContentFilter? fromWire(Object? value) =>
      _byWire(values, value);
}

/// Discord's `default_message_notifications`.
///
/// The renderer's frozen enum continues past [noMessages] with entries R23
/// could not read, which is exactly why [fromWire] answers `null` for anything
/// it does not recognise instead of guessing at the tail.
enum GuildNotificationLevel implements GuildWireEnum {
  allMessages(0),
  onlyMentions(1),
  noMessages(2);

  const GuildNotificationLevel(this.wireValue);

  @override
  final int wireValue;

  /// What Discord's own overview page offers. The third value exists on the
  /// wire but that surface never sets it, and shipping a control the official
  /// client does not have is how a client invents behaviour.
  static const selectable = [allMessages, onlyMentions];

  static GuildNotificationLevel? fromWire(Object? value) =>
      _byWire(values, value);
}

/// Discord's `mfa_level`.
enum GuildMfaLevel implements GuildWireEnum {
  none(0),
  elevated(1);

  const GuildMfaLevel(this.wireValue);

  @override
  final int wireValue;

  static GuildMfaLevel? fromWire(Object? value) => _byWire(values, value);
}

/// Bits of `system_channel_flags`. Every one of them suppresses something, so
/// a set bit means the notification is *off*.
abstract final class GuildSystemChannelFlags {
  static const suppressJoinNotifications = 1;
  static const suppressPremiumSubscriptions = 2;
  static const suppressGuildReminderNotifications = 4;
  static const suppressJoinNotificationReplies = 8;
  static const suppressRoleSubscriptionPurchaseNotifications = 16;
  static const suppressRoleSubscriptionPurchaseNotificationReplies = 32;
  static const suppressChannelPromptDeadchat = 128;
  static const suppressVoiceSessionNotifications = 512;

  static bool has(int flags, int bit) => flags & bit == bit;

  /// Sets or clears [bit] without disturbing the bits this client has no name
  /// for — a guild may carry flags a newer Discord added, and a settings save
  /// must not clear them just because this build cannot render them.
  static int withFlag(int flags, int bit, {required bool enabled}) =>
      enabled ? flags | bit : flags & ~bit;
}

/// A guild's settings as the server last reported them.
final class GuildOverviewSettings {
  const GuildOverviewSettings({
    required this.id,
    required this.name,
    this.iconHash,
    this.description,
    this.ownerId,
    this.preferredLocale,
    this.afkChannelId,
    this.afkTimeoutSeconds = 300,
    this.systemChannelId,
    this.systemChannelFlags = 0,
    this.verificationLevel,
    this.explicitContentFilter,
    this.defaultMessageNotifications,
    this.mfaLevel,
    this.premiumProgressBarEnabled = false,
    this.features = const <String>{},
  });

  final String id;
  final String name;
  final String? iconHash;
  final String? description;
  final String? ownerId;
  final String? preferredLocale;
  final String? afkChannelId;
  final int afkTimeoutSeconds;
  final String? systemChannelId;
  final int systemChannelFlags;
  final GuildVerificationLevel? verificationLevel;
  final GuildExplicitContentFilter? explicitContentFilter;
  final GuildNotificationLevel? defaultMessageNotifications;
  final GuildMfaLevel? mfaLevel;
  final bool premiumProgressBarEnabled;

  /// Feature flags. A `Set` here and a JSON array on the wire, matching the
  /// renderer, which patches `Set.prototype.toJSON` to do the same.
  final Set<String> features;

  /// The AFK timeouts Discord's overview page offers, in seconds.
  static const afkTimeoutChoices = [60, 300, 900, 1800, 3600];
}

/// A partial `PATCH /guilds/{id}`.
///
/// Every field is tri-state and the encoding is deliberate: absent from
/// [_values] means "leave it alone", present-and-null means "clear it". Discord
/// distinguishes the two — `afk_channel_id: null` removes the AFK channel,
/// omitting the key keeps it — and a patch type that could not say both would
/// force the settings form to send every field it ever read back, turning an
/// unrelated edit into a full overwrite of a guild it may only partly
/// understand.
final class GuildOverviewPatch {
  GuildOverviewPatch();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;

  /// The keys this patch will send, for tests and for a confirmation summary.
  Iterable<String> get keys => _values.keys;

  bool contains(String key) => _values.containsKey(key);
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;
  set description(String? value) => _values['description'] = value;

  /// A `data:` URI to replace the icon, or `null` to clear it.
  ///
  /// A CDN hash is deliberately not accepted: the renderer forwards `icon` only
  /// when it is null or a data URI, and sending a hash back is how a client
  /// ends up asking the server to interpret its own filename.
  set icon(String? value) {
    if (value != null && !value.startsWith('data:')) {
      throw ArgumentError.value(value, 'icon', 'Expected null or a data: URI');
    }
    _values['icon'] = value;
  }

  set preferredLocale(String value) => _values['preferred_locale'] = value;
  set afkChannelId(String? value) => _values['afk_channel_id'] = value;
  set afkTimeoutSeconds(int value) => _values['afk_timeout'] = value;
  set systemChannelId(String? value) => _values['system_channel_id'] = value;
  set systemChannelFlags(int value) => _values['system_channel_flags'] = value;

  set verificationLevel(GuildVerificationLevel value) =>
      _values['verification_level'] = value.wireValue;

  set explicitContentFilter(GuildExplicitContentFilter value) =>
      _values['explicit_content_filter'] = value.wireValue;

  set defaultMessageNotifications(GuildNotificationLevel value) =>
      _values['default_message_notifications'] = value.wireValue;

  set premiumProgressBarEnabled(bool value) =>
      _values['premium_progress_bar_enabled'] = value;

  /// The JSON body. Nulls survive because on this route they mean "clear".
  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(_values);
}

T? _byWire<T extends GuildWireEnum>(List<T> values, Object? value) {
  final wire = switch (value) {
    final int raw => raw,
    final String raw => int.tryParse(raw),
    _ => null,
  };
  if (wire == null) return null;
  for (final candidate in values) {
    if (candidate.wireValue == wire) return candidate;
  }
  return null;
}
