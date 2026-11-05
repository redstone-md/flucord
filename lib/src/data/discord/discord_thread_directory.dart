import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/forum_repository.dart';
import '../../domain/thread_repository.dart';
import 'discord_mapper.dart';
import 'discord_multipart_body.dart';
import 'discord_rest_client.dart';

/// The thread routes a user account and a bot share.
final class DiscordThreadRoutes {
  const DiscordThreadRoutes(this._rest);

  final DiscordRestClient _rest;

  /// `GET /channels/{id}/threads/search`, which Discord's own client uses for
  /// forums and the thread browser: active and archived threads together, and
  /// in a forum the opening message of each in `first_messages`. While the
  /// channel is still being indexed it answers 202 with a `retry_after` and no
  /// threads.
  Future<Map<String, Object?>> searchThreads(
    String channelId, {
    required int offset,
    required Set<String> tagIds,
  }) => _rest.requestObject(
    'GET',
    '/channels/$channelId/threads/search',
    query: {
      'sort_by': 'last_message_time',
      'sort_order': 'desc',
      'limit': '${DiscordThreadDirectory.pageSize}',
      'offset': '$offset',
      if (tagIds.isNotEmpty) ...{'tag': tagIds, 'tag_setting': 'match_some'},
    },
  );

  Future<Map<String, Object?>> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    required List<PendingAttachment> attachments,
    required List<String> appliedTagIds,
  }) async {
    final payload = <String, Object?>{
      'name': name,
      'auto_archive_duration': autoArchiveDurationMinutes,
      'message': {
        'content': content,
        if (attachments.isNotEmpty)
          'attachments': [
            for (var index = 0; index < attachments.length; index++)
              {'id': index, 'filename': attachments[index].name},
          ],
      },
      if (appliedTagIds.isNotEmpty) 'applied_tags': appliedTagIds,
    };
    final path = '/channels/$channelId/threads';
    if (attachments.isEmpty) {
      return _rest.requestObject('POST', path, body: payload);
    }
    final multipart = await DiscordMultipartBody.build(payload, attachments);
    final response = await _rest.request(
      'POST',
      path,
      rawBody: multipart.bytes,
      contentType: multipart.contentType,
    );
    if (response is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return response.cast<String, Object?>();
  }
}

/// Lists the threads under a channel and opens forum posts, storing what
/// Discord answers in the cache. Both Discord repositories hand their thread
/// work to one of these.
final class DiscordThreadDirectory {
  DiscordThreadDirectory({
    required DiscordThreadRoutes routes,
    required ChatCache cache,
    required DiscordMapper mapper,
    required String? Function() currentMemberId,
    void Function(Map<String, Object?> member)? onSelfMember,
    Future<void> Function(Duration)? wait,
  }) : _routes = routes,
       _cache = cache,
       _mapper = mapper,
       _currentMemberId = currentMemberId,
       _onSelfMember = onSelfMember,
       _wait = wait ?? Future<void>.delayed;

  /// The most threads Discord returns at once.
  static const pageSize = 25;

  /// How often a channel still being indexed is asked before giving up.
  static const _indexingAttempts = 3;

  final DiscordThreadRoutes _routes;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final String? Function() _currentMemberId;
  final void Function(Map<String, Object?> member)? _onSelfMember;
  final Future<void> Function(Duration) _wait;

  Future<ThreadPage> loadThreads(
    String parentId, {
    required int offset,
    required Set<String> tagIds,
  }) async {
    final parent = await _cachedParent(parentId);
    Future<Map<String, Object?>> search() =>
        _routes.searchThreads(parentId, offset: offset, tagIds: tagIds);
    var payload = await search();
    for (
      var attempt = 1;
      attempt < _indexingAttempts && payload['threads'] is! List;
      attempt++
    ) {
      final retryAfter = payload['retry_after'];
      if (retryAfter is! num) break;
      await _wait(
        Duration(milliseconds: (retryAfter * 1000).clamp(500, 5000).round()),
      );
      payload = await search();
    }
    if (payload['threads'] is! List) {
      throw const DiscordApiException(
        statusCode: 202,
        message: 'Discord is still indexing these threads',
      );
    }
    final threads = _objects(
      payload['threads'],
    ).map((raw) => _thread(raw, parent.spaceId)).toList(growable: false);
    final firstMessages = _objects(payload['first_messages'])
        .map((raw) => _mapper.message(raw, currentMemberId: _currentMemberId()))
        .toList(growable: false);
    for (final thread in threads) {
      await _cache.writeChannel(thread);
    }
    for (final message in firstMessages) {
      await _cache.writeMessage(message);
    }
    // One entry for each listed thread this account has joined.
    if (_onSelfMember case final accept?) {
      _objects(payload['members']).forEach(accept);
    }
    return ThreadPage(
      threads: threads,
      firstMessages: firstMessages,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<CreatedForumPost> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    required List<PendingAttachment> attachments,
    required List<String> appliedTagIds,
  }) async {
    final parent = await _cachedParent(channelId);
    if (parent.kind != ChannelKind.forum && parent.kind != ChannelKind.media) {
      throw StateError('Only a forum or media channel takes posts');
    }
    final payload = await _routes.createForumPost(
      channelId: channelId,
      name: name,
      content: content,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
      attachments: attachments,
      appliedTagIds: appliedTagIds,
    );
    final thread = _thread(payload, parent.spaceId);
    final rawMessage = payload['message'];
    if (rawMessage is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a Discord forum starter message',
      );
    }
    final message = _mapper.message(
      rawMessage.cast<String, Object?>(),
      currentMemberId: _currentMemberId(),
    );
    await _cache.writeChannel(thread);
    await _cache.writeMessage(message);
    return CreatedForumPost(thread: thread, initialMessage: message);
  }

  Future<ConversationChannel> _cachedParent(String channelId) async {
    final parent = (await _cache.readWorkspaceShell())?.channelOrNull(
      channelId,
    );
    if (parent == null) throw StateError('Parent channel is not cached');
    return parent;
  }

  ConversationChannel _thread(Map<String, Object?> payload, String guildId) {
    final thread = _mapper.channel(
      payload,
      payload['guild_id'] as String? ?? guildId,
    );
    if (thread == null || !thread.isThread) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a Discord thread channel',
      );
    }
    return thread;
  }

  static Iterable<Map<String, Object?>> _objects(Object? raw) =>
      (raw is List ? raw : const <Object?>[]).whereType<Map>().map(
        (item) => item.cast<String, Object?>(),
      );
}
