/// What a Go Live stream is filed under.
///
/// Discord addresses a stream by a composed key rather than an id, because the
/// stream exists before the server has assigned it anything: the key names the
/// room and the person, and every later frame — watch, ping, pause, delete —
/// carries it back.
final class GoLiveStreamKey {
  /// A stream in a guild's voice channel.
  const GoLiveStreamKey.guild({
    required String this.guildId,
    required this.channelId,
    required this.userId,
  });

  /// A stream in a DM or group-DM call, which has no guild.
  const GoLiveStreamKey.call({required this.channelId, required this.userId})
    : guildId = null;

  final String? guildId;
  final String channelId;
  final String userId;

  bool get isCall => guildId == null;

  /// `guild:<guild>:<channel>:<user>` or `call:<channel>:<user>`.
  ///
  /// Discord parses this string apart on its side, so the shape is part of the
  /// protocol rather than a local convenience.
  String get value =>
      isCall ? 'call:$channelId:$userId' : 'guild:$guildId:$channelId:$userId';

  /// Reads a key back, or `null` when the string is not one.
  static GoLiveStreamKey? parse(String value) {
    final parts = value.split(':');
    if (parts.length == 4 && parts.first == 'guild') {
      if (parts.any((part) => part.isEmpty)) return null;
      return GoLiveStreamKey.guild(
        guildId: parts[1],
        channelId: parts[2],
        userId: parts[3],
      );
    }
    if (parts.length == 3 && parts.first == 'call') {
      if (parts.any((part) => part.isEmpty)) return null;
      return GoLiveStreamKey.call(channelId: parts[1], userId: parts[2]);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is GoLiveStreamKey &&
      other.guildId == guildId &&
      other.channelId == channelId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(guildId, channelId, userId);

  @override
  String toString() => value;
}

/// Where a stream is in its life.
enum GoLiveStatus {
  /// Not streaming.
  idle,

  /// The create frame went out; Discord has not answered yet.
  creating,

  /// `STREAM_CREATE` came back and the RTC endpoint is being negotiated.
  connecting,

  /// Live, and being sent.
  live,

  /// Live, but the sender is holding frames back.
  paused,

  failure,
}

/// The RTC endpoint Discord assigned a stream.
final class GoLiveServer {
  const GoLiveServer({
    required this.key,
    required this.endpoint,
    required this.token,
    this.rtcServerId = '',
    this.rtcChannelId = '',
  });

  final GoLiveStreamKey key;
  final String endpoint;
  final String token;

  /// What the connection identifies against.
  ///
  /// Discord assigns a stream its own RTC server and names it in
  /// `STREAM_CREATE`; it is not the guild id, and identifying with the guild
  /// is answered with 4006 — "that session is no longer valid". Empty when
  /// the create has not been seen, where the guild is the best guess left.
  final String rtcServerId;

  /// The channel that RTC server knows the stream by.
  ///
  /// Not the voice channel: `STREAM_CREATE` names both, and a connection
  /// identifying with the voice one is refused. Empty when the create has not
  /// been seen.
  final String rtcChannelId;
}

/// One stream, ours or somebody else's.
final class GoLiveStream {
  const GoLiveStream({
    required this.key,
    this.rtcServerId = '',
    this.rtcChannelId = '',
    this.region = '',
    this.viewerIds = const [],
    this.isPaused = false,
  });

  final GoLiveStreamKey key;
  final String rtcServerId;

  /// The channel the RTC server knows this stream by, from the same create.
  final String rtcChannelId;
  final String region;

  /// Who is watching. Discord reports this on every change rather than as a
  /// count, so the surface can name them.
  final List<String> viewerIds;

  final bool isPaused;

  GoLiveStream copyWith({
    String? rtcServerId,
    String? rtcChannelId,
    String? region,
    List<String>? viewerIds,
    bool? isPaused,
  }) => GoLiveStream(
    key: key,
    rtcServerId: rtcServerId ?? this.rtcServerId,
    rtcChannelId: rtcChannelId ?? this.rtcChannelId,
    region: region ?? this.region,
    viewerIds: viewerIds ?? this.viewerIds,
    isPaused: isPaused ?? this.isPaused,
  );
}

/// Starting, watching and ending a Go Live stream.
abstract interface class GoLiveRepository {
  /// Streams this session knows about, keyed by their string form.
  Map<String, GoLiveStream> get streams;

  /// Fires whenever any stream changes.
  Stream<GoLiveStream> get updates;

  /// Fires when Discord hands out an RTC endpoint for a stream.
  Stream<GoLiveServer> get servers;

  /// Opens a stream in the voice channel this account is in.
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  });

  /// Asks to watch somebody else's stream.
  Future<void> watchStream(GoLiveStreamKey key);

  /// Tells Discord the stream is still alive. Sent on a timer while live.
  Future<void> pingStream(GoLiveStreamKey key);

  /// Holds frames back without tearing the stream down.
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused});

  /// Ends it.
  Future<void> endStream(GoLiveStreamKey key);
}
