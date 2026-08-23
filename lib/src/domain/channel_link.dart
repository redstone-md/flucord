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
