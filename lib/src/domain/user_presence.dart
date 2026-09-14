part of 'chat_models.dart';

/// The devices `presence.client_status` is keyed by, R07's platform enum.
///
/// `unknown` is a real member of Discord's enum rather than a Flucord
/// fallback, and a key this build does not recognise folds into it so that a
/// new device type still counts as "online somewhere".
enum ClientPlatform {
  desktop('desktop'),
  web('web'),
  mobile('mobile'),
  vr('vr'),
  unknown('unknown');

  const ClientPlatform(this.wireValue);

  final String wireValue;

  static ClientPlatform fromWire(Object? value) => switch (value) {
    'desktop' => desktop,
    'web' => web,
    'mobile' => mobile,
    'vr' => vr,
    _ => unknown,
  };
}

/// Everything Discord knows about one user's presence, after the per-guild
/// entries have been collapsed into a single answer.
final class UserPresence {
  const UserPresence({
    this.status = Presence.offline,
    this.clientStatus = const {},
    this.activities = const [],
    this.hiddenActivities = const [],
  });

  static const offline = UserPresence();

  final Presence status;

  /// Which device reports which status. Empty for a user whose presence
  /// arrived without the map, which is not the same as being on no device.
  final Map<ClientPlatform, Presence> clientStatus;

  final List<UserActivity> activities;

  /// Activities the server marked hidden. Kept because they still decide
  /// whether an otherwise-offline user is dropped from the presence map.
  final List<UserActivity> hiddenActivities;

  /// R07: mobile is only reported as such while no desktop or VR client is
  /// also online, which is what makes the phone glyph mean "only on mobile".
  bool get isMobileOnly =>
      clientStatus[ClientPlatform.mobile] == Presence.online &&
      clientStatus[ClientPlatform.desktop] != Presence.online &&
      clientStatus[ClientPlatform.vr] != Presence.online;

  bool get isVrOnline => clientStatus[ClientPlatform.vr] == Presence.online;

  UserActivity? get customStatus {
    for (final activity in activities) {
      if (activity.type == ActivityType.customStatus) return activity;
    }
    return null;
  }

  /// The activity a member row summarises. R07 excludes `HANG_STATUS` from the
  /// primary slot, and a custom status loses to anything the user is doing.
  UserActivity? get primaryActivity {
    UserActivity? custom;
    for (final activity in activities) {
      if (activity.type == ActivityType.hangStatus) continue;
      if (activity.type == ActivityType.customStatus) {
        custom ??= activity;
        continue;
      }
      return activity;
    }
    return custom;
  }

  /// The activity a profile card draws artwork for, or null when the user is
  /// only carrying a custom status.
  UserActivity? get richActivity {
    for (final activity in activities) {
      if (activity.type == ActivityType.customStatus) continue;
      if (activity.type == ActivityType.hangStatus) continue;
      if (activity.isRichPresence) return activity;
    }
    return null;
  }

  bool get isStreaming =>
      activities.any((activity) => activity.type == ActivityType.streaming);

  /// The status a status dot paints.
  ///
  /// R07: `streaming` never arrives on the wire — it is synthesised at render
  /// time from the activity list — so it is derived here rather than stored.
  Presence get displayStatus =>
      isStreaming && status.isOnline ? Presence.streaming : status;

  bool get isEmpty =>
      status == Presence.offline &&
      activities.isEmpty &&
      hiddenActivities.isEmpty;

  UserPresence copyWith({
    Presence? status,
    Map<ClientPlatform, Presence>? clientStatus,
    List<UserActivity>? activities,
    List<UserActivity>? hiddenActivities,
  }) => UserPresence(
    status: status ?? this.status,
    clientStatus: clientStatus ?? this.clientStatus,
    activities: activities ?? this.activities,
    hiddenActivities: hiddenActivities ?? this.hiddenActivities,
  );
}

/// One of the account's other logged-in clients, from `SESSIONS_REPLACE`.
final class UserSession {
  const UserSession({
    required this.sessionId,
    this.status = Presence.offline,
    this.lastModified = 0,
    this.activities = const [],
    this.hiddenActivities = const [],
    this.active = false,
    this.operatingSystem,
  });

  final String sessionId;
  final Presence status;
  final int lastModified;
  final List<UserActivity> activities;
  final List<UserActivity> hiddenActivities;
  final bool active;

  /// `client_info.os`. R07 records this as the only key the renderer reads, so
  /// the rest of `client_info` is deliberately not modelled.
  final String? operatingSystem;
}

/// The `{status, since, activities, afk}` object opcode 3 sends and IDENTIFY
/// embeds — R07 proves the two are the same shape.
final class SelfPresence {
  const SelfPresence({
    this.status = Presence.online,
    this.since = 0,
    this.activities = const [],
    this.afk = false,
  });

  final Presence status;

  /// The last-input timestamp in milliseconds while idle, `0` otherwise.
  final int since;

  final List<UserActivity> activities;
  final bool afk;

  SelfPresence copyWith({
    Presence? status,
    int? since,
    List<UserActivity>? activities,
    bool? afk,
  }) => SelfPresence(
    status: status ?? this.status,
    since: since ?? this.since,
    activities: activities ?? this.activities,
    afk: afk ?? this.afk,
  );
}
