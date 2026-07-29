/// What streamer mode hides while it is on.
///
/// The switches are Discord's own, read out of the desktop bundle's settings
/// ids rather than invented: hide personal information, hide invite links,
/// disable sounds, disable notifications. Its two remaining switches — hiding
/// the window from screen capture, and hiding overlay widgets — need
/// capabilities this build does not have, and are left out rather than shown
/// as toggles that change nothing.
final class StreamerModeSettings {
  const StreamerModeSettings({
    this.enabled = false,
    this.automatic = true,
    this.hidePersonalInformation = true,
    this.hideInviteLinks = true,
    this.disableSounds = true,
    this.disableNotifications = true,
  });

  /// Whether it is on right now.
  final bool enabled;

  /// Whether starting a stream turns it on by itself, which is Discord's
  /// default and the reason the mode is usable at all: somebody about to go
  /// live is not thinking about a settings page.
  final bool automatic;

  final bool hidePersonalInformation;
  final bool hideInviteLinks;
  final bool disableSounds;
  final bool disableNotifications;

  static const off = StreamerModeSettings();

  bool get hidesPersonalInformation => enabled && hidePersonalInformation;
  bool get hidesInviteLinks => enabled && hideInviteLinks;
  bool get silencesSounds => enabled && disableSounds;
  bool get silencesNotifications => enabled && disableNotifications;

  StreamerModeSettings copyWith({
    bool? enabled,
    bool? automatic,
    bool? hidePersonalInformation,
    bool? hideInviteLinks,
    bool? disableSounds,
    bool? disableNotifications,
  }) => StreamerModeSettings(
    enabled: enabled ?? this.enabled,
    automatic: automatic ?? this.automatic,
    hidePersonalInformation:
        hidePersonalInformation ?? this.hidePersonalInformation,
    hideInviteLinks: hideInviteLinks ?? this.hideInviteLinks,
    disableSounds: disableSounds ?? this.disableSounds,
    disableNotifications: disableNotifications ?? this.disableNotifications,
  );

  Map<String, Object?> toJson() => {
    // `enabled` is deliberately not stored: the mode is about what is on
    // screen right now, and a client that came back up still hiding
    // everything would leave somebody wondering what broke.
    'automatic': automatic,
    'hide_personal_information': hidePersonalInformation,
    'hide_invite_links': hideInviteLinks,
    'disable_sounds': disableSounds,
    'disable_notifications': disableNotifications,
  };

  /// Reads stored settings, falling back per field.
  ///
  /// A file written by a newer build, or edited by hand, must not stop the
  /// client: an unreadable switch simply keeps its default.
  static StreamerModeSettings fromJson(Object? value) {
    if (value is! Map) return const StreamerModeSettings();
    bool read(String key, {required bool fallback}) {
      final held = value[key];
      return held is bool ? held : fallback;
    }

    return StreamerModeSettings(
      automatic: read('automatic', fallback: true),
      hidePersonalInformation: read(
        'hide_personal_information',
        fallback: true,
      ),
      hideInviteLinks: read('hide_invite_links', fallback: true),
      disableSounds: read('disable_sounds', fallback: true),
      disableNotifications: read('disable_notifications', fallback: true),
    );
  }
}

/// Where the switches are kept.
///
/// Local rather than on the account: `PreloadedUserSettings` has no streamer
/// group — the desktop client keeps these on the machine — so putting them in
/// the settings blob would invent a shape Discord does not have.
abstract interface class StreamerModeRepository {
  Future<StreamerModeSettings> load();
  Future<void> save(StreamerModeSettings settings);
}

/// What an invite link is replaced with while the mode is on.
const String hiddenInviteLabel = '[invite hidden]';

/// Replaces every Discord invite link in [text].
///
/// Matched by host rather than by shape: `discord.gg/x` is an invite and
/// `example.com/discord.gg` is not, and a viewer of a stream reading the
/// second as the first is only a nuisance while the reverse hands out a
/// server to everybody watching.
String hideInviteLinks(String text) => text.replaceAllMapped(
  RegExp(
    r'(?:https?://)?(?:www\.)?'
    r'(?:discord\.gg|discord(?:app)?\.com/invite|discord\.com/events)'
    r'/[A-Za-z0-9\-_/]+',
    caseSensitive: false,
  ),
  (_) => hiddenInviteLabel,
);
