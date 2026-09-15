final class ChannelLink {
  const ChannelLink({required this.spaceId, required this.channelId});

  static const scheme = 'flucord';
  static const host = 'channels';

  final String spaceId;
  final String channelId;

  Uri toUri() =>
      Uri(scheme: scheme, host: host, pathSegments: [spaceId, channelId]);

  static ChannelLink? tryParse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != scheme ||
        uri.host.toLowerCase() != host ||
        uri.pathSegments.length != 2 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final spaceId = uri.pathSegments[0].trim();
    final channelId = uri.pathSegments[1].trim();
    if (spaceId.isEmpty || channelId.isEmpty) return null;
    return ChannelLink(spaceId: spaceId, channelId: channelId);
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelLink &&
      other.spaceId == spaceId &&
      other.channelId == channelId;

  @override
  int get hashCode => Object.hash(spaceId, channelId);
}

/// A Discord invite link, parsed to the code a join surface asks for.
///
/// Discord hands invites around in three URL forms and one bare form:
/// `https://discord.gg/{code}`, `https://discord.com/invite/{code}`,
/// `https://discord.gg/invite/{code}`, and a plain code pasted as text. This
/// is the surface that already owns the app's link shapes, so the invite
/// forms live here beside the app's own deep links.
final class InviteLink {
  const InviteLink({required this.code});

  /// Discord's invite hosts. The short one is what people share; the long one
  /// is what the app and the site themselves generate.
  static const _hosts = {'discord.gg', 'discord.com', 'ptb.discord.com'};

  final String code;

  /// The code embedded in [value], or null when it names no invite.
  ///
  /// A query or fragment is ignored rather than rejected: Discord's own links
  /// carry one (`?event=123`), and it is the code that the join surface needs.
  static String? tryParseCode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    final code = _codeFromUri(uri) ?? _codeAsPlain(trimmed);
    if (code == null || code.isEmpty) return null;
    return code;
  }

  static String? _codeFromUri(Uri? uri) {
    if (uri == null || !uri.hasScheme) return null;
    final host = uri.host.toLowerCase();
    if (!_hosts.contains(host)) return null;
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.trim().isNotEmpty) segment.trim(),
    ];
    // `discord.gg/{code}` and `discord.com/invite/{code}`; the short host
    // also serves the `/invite/` spelling.
    if (host != 'discord.com' && host != 'ptb.discord.com') {
      return segments.length == 1
          ? segments.single
          : segments.length == 2 && segments.first == 'invite'
          ? segments[1]
          : null;
    }
    return segments.length == 2 && segments.first == 'invite'
        ? segments[1]
        : null;
  }

  /// A bare invite code. Discord's codes are case-sensitive short strings
  /// without dots, spaces or slashes, so anything that cannot be one is not
  /// mistaken for one.
  static String? _codeAsPlain(String value) {
    if (value.contains('/') || value.contains('.') || value.contains(' ')) {
      return null;
    }
    return value;
  }
}

/// A Discord message or channel link, the shape the site and the app itself
/// hand around for a conversation.
///
/// `https://discord.com/channels/{guild}/{channel}` names a channel and the
/// same path with one more segment lands on a message. The guild segment can
/// be `@me`, which is how a direct-message conversation is addressed. The host
/// carries the release channel Discord publishes on; the path is what names
/// the destination, so a query or fragment is ignored rather than rejected.
final class DiscordMessageLink {
  const DiscordMessageLink({
    required this.spaceId,
    required this.channelId,
    this.messageId,
  });

  /// Discord's conversation-link hosts. The bare one is the site itself; the
  /// other two are the public test and canary builds of the same site.
  static const _hosts = {
    'discord.com',
    'ptb.discord.com',
    'canary.discord.com',
  };

  /// The guild the link names, or `@me` for a direct-message conversation.
  final String spaceId;
  final String channelId;

  /// The message the link lands on, or null when it names only a channel.
  final String? messageId;

  /// The link embedded in [value], or null when it names no conversation.
  static DiscordMessageLink? tryParse(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    if (!_hosts.contains(uri.host.toLowerCase())) return null;
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.trim().isNotEmpty) segment.trim(),
    ];
    if (segments.length < 3 || segments.first != 'channels') return null;
    if (segments.length > 4) return null;
    return DiscordMessageLink(
      spaceId: segments[1],
      channelId: segments[2],
      messageId: segments.length == 4 ? segments[3] : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscordMessageLink &&
      other.spaceId == spaceId &&
      other.channelId == channelId &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(spaceId, channelId, messageId);
}
