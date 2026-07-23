import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  group('DiscordApiClient', () {
    test('retries a documented 429 without private client headers', () async {
      final transport = _RecordingTransport([
        const DiscordHttpResponse(
          statusCode: 429,
          headers: {},
          body: '{"message":"rate limited","retry_after":0.25}',
        ),
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"id":"bot-1","username":"Flucord"}',
        ),
      ]);
      final delays = <Duration>[];
      final client = DiscordApiClient(
        botToken: 'secret-token',
        transport: transport,
        delay: (duration) async => delays.add(duration),
      );

      final user = await client.getCurrentUser();

      expect(user['id'], 'bot-1');
      expect(delays, [const Duration(milliseconds: 250)]);
      expect(transport.requests, hasLength(2));
      final headers = transport.requests.first.headers;
      expect(headers['authorization'], 'Bot secret-token');
      expect(headers['accept'], 'application/json');
      expect(headers['content-type'], 'application/json');
      expect(headers, isNot(contains('x-super-properties')));
      expect(headers, isNot(contains('x-fingerprint')));
    });

    test(
      'sends message content as JSON and never exposes token in errors',
      () async {
        final successTransport = _RecordingTransport([
          const DiscordHttpResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"id":"m1","channel_id":"c1","content":"hello","timestamp":"2026-07-23T02:00:00Z","author":{"id":"bot-1"}}',
          ),
        ]);
        final client = DiscordApiClient(
          botToken: 'secret-token',
          transport: successTransport,
        );

        await client.createMessage(channelId: 'c1', content: 'hello');

        final request = successTransport.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v10/channels/c1/messages');
        expect(jsonDecode(utf8.decode(request.body!))['content'], 'hello');

        final rejected = DiscordApiClient(
          botToken: 'never-print-this',
          transport: _RecordingTransport([
            const DiscordHttpResponse(
              statusCode: 401,
              headers: {},
              body: '{"message":"401: Unauthorized"}',
            ),
          ]),
        );
        await expectLater(
          rejected.getCurrentUser(),
          throwsA(
            isA<DiscordApiException>()
                .having((error) => error.isUnauthorized, 'unauthorized', isTrue)
                .having(
                  (error) => error.toString(),
                  'redacted message',
                  isNot(contains('never-print-this')),
                ),
          ),
        );
      },
    );

    test('sends documented multipart replies and message actions', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-test-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}notes.txt');
      await file.writeAsString('attachment bytes');
      final transport = _RecordingTransport([
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"id":"m2"}',
        ),
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"id":"m2","content":"edited"}',
        ),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final client = DiscordApiClient(botToken: 'token', transport: transport);

      await client.createMessage(
        channelId: 'c1',
        content: 'reply',
        replyToMessageId: 'm1',
        attachments: [
          PendingAttachment(name: 'notes.txt', path: file.path, size: 16),
        ],
      );
      await client.editMessage(
        channelId: 'c1',
        messageId: 'm2',
        content: 'edited',
      );
      await client.deleteMessage(channelId: 'c1', messageId: 'm2');
      await client.addReaction(
        channelId: 'c1',
        messageId: 'm1',
        emoji: 'check:42',
      );
      await client.removeReaction(
        channelId: 'c1',
        messageId: 'm1',
        emoji: 'check:42',
      );

      final multipart = transport.requests.first;
      expect(
        multipart.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      final multipartText = utf8.decode(multipart.body!);
      expect(multipartText, contains('name="payload_json"'));
      expect(multipartText, contains('"message_id":"m1"'));
      expect(multipartText, contains('name="files[0]"'));
      expect(multipartText, contains('attachment bytes'));
      expect(transport.requests[1].method, 'PATCH');
      expect(transport.requests[2].method, 'DELETE');
      expect(transport.requests[3].uri.toString(), contains('check%3A42/@me'));
      expect(transport.requests[4].method, 'DELETE');
    });

    test('uses documented pins, members, roles, and typing routes', () async {
      final transport = _RecordingTransport([
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '[{"id":"role-1","name":"Operator"}]',
        ),
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '[{"user":{"id":"user-1"}}]',
        ),
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"items":[{"pinned_at":"2026-07-23T01:00:00Z","message":{"id":"m1"}}],"has_more":false}',
        ),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final client = DiscordApiClient(botToken: 'token', transport: transport);

      expect(await client.getGuildRoles('g1'), hasLength(1));
      expect(await client.getGuildMembers('g1'), hasLength(1));
      final pins = await client.getChannelPins('c1');
      await client.pinMessage(channelId: 'c1', messageId: 'm1');
      await client.unpinMessage(channelId: 'c1', messageId: 'm1');
      await client.startTyping('c1');

      expect(pins.single['pinned'], isTrue);
      expect(transport.requests[1].uri.queryParameters['limit'], '1000');
      expect(
        transport.requests[2].uri.path,
        '/api/v10/channels/c1/messages/pins',
      );
      expect(transport.requests[3].method, 'PUT');
      expect(transport.requests[4].method, 'DELETE');
      expect(transport.requests[5].uri.path, '/api/v10/channels/c1/typing');
    });

    test('paginates message history with a bounded before cursor', () async {
      final transport = _RecordingTransport([
        const DiscordHttpResponse(statusCode: 200, headers: {}, body: '[]'),
      ]);
      final client = DiscordApiClient(botToken: 'token', transport: transport);

      await client.getChannelMessages(
        'c1',
        limit: 250,
        beforeMessageId: 'message-100',
      );

      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/v10/channels/c1/messages');
      expect(request.uri.queryParameters['limit'], '100');
      expect(request.uri.queryParameters['before'], 'message-100');
    });

    test('opens a documented bot direct message channel', () async {
      final transport = _RecordingTransport([
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"id":"dm-1","type":1,"recipients":[{"id":"123456789012345678","username":"Jack"}]}',
        ),
      ]);
      final client = DiscordApiClient(botToken: 'token', transport: transport);

      final channel = await client.createDirectMessageChannel(
        '123456789012345678',
      );

      expect(channel['id'], 'dm-1');
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v10/users/@me/channels');
      expect(
        jsonDecode(utf8.decode(request.body!))['recipient_id'],
        '123456789012345678',
      );
    });
  });

  test('gateway protocol identifies then resumes the same session', () {
    final protocol = DiscordGatewayProtocol(
      token: 'bot-token',
      intents:
          DiscordGatewayClient.guildsIntent |
          DiscordGatewayClient.guildMembersIntent |
          DiscordGatewayClient.guildPresencesIntent |
          DiscordGatewayClient.guildMessagesIntent |
          DiscordGatewayClient.guildMessageReactionsIntent |
          DiscordGatewayClient.guildMessageTypingIntent |
          DiscordGatewayClient.directMessagesIntent |
          DiscordGatewayClient.directMessageReactionsIntent |
          DiscordGatewayClient.directMessageTypingIntent |
          DiscordGatewayClient.messageContentIntent,
    );

    final identify = protocol.identify();
    expect(identify['op'], 2);
    final identifyData = identify['d']! as Map<String, Object?>;
    expect(identifyData['token'], 'bot-token');
    expect(identifyData['intents'], 65283);
    expect(identifyData['large_threshold'], 250);

    protocol.accept({
      'op': 0,
      's': 41,
      't': 'READY',
      'd': {
        'session_id': 'session-1',
        'resume_gateway_url': 'wss://resume.discord.gg',
      },
    });

    expect(protocol.canResume, isTrue);
    expect(protocol.heartbeat(), {'op': 1, 'd': 41});
    expect(protocol.resume()['op'], 6);
    expect((protocol.resume()['d']! as Map)['session_id'], 'session-1');
  });

  test('mapper translates guilds, channels, authors, and message order', () {
    final mapper = DiscordMapper();
    final workspace = mapper.workspace(
      currentUser: {
        'id': 'bot-1',
        'username': 'Flucord Bot',
        'global_name': null,
        'avatar': 'bot-avatar',
      },
      guilds: [
        {'id': 'guild-1', 'name': 'The Forge', 'icon': 'guild-icon'},
      ],
      channelsByGuild: {
        'guild-1': [
          {'id': 'category-1', 'name': 'Category', 'type': 4, 'position': 0},
          {
            'id': 'channel-1',
            'name': 'general',
            'type': 0,
            'topic': 'Build notes',
            'position': 1,
          },
        ],
      },
      rolesByGuild: {
        'guild-1': [
          {
            'id': 'role-1',
            'name': 'Operator',
            'position': 5,
            'color': 0x336699,
          },
        ],
      },
      membersByGuild: {
        'guild-1': [
          {
            'nick': 'Mira Ops',
            'avatar': 'member-avatar',
            'roles': ['role-1'],
            'user': {
              'id': 'user-1',
              'username': 'Mira',
              'global_name': null,
              'avatar': 'global-avatar',
            },
          },
        ],
      },
    );
    final history = mapper.history('channel-1', [
      _messagePayload(id: 'new', minute: 2),
      _messagePayload(id: 'old', minute: 1, mentionBot: true),
    ], currentMemberId: 'bot-1');

    expect(workspace.spaces.single.name, 'The Forge');
    expect(workspace.spaces.single.iconUrl, contains('/icons/guild-1/'));
    expect(workspace.channels.single.name, 'general');
    expect(workspace.roles.single.name, 'Operator');
    expect(workspace.roles.single.colorValue, 0xff336699);
    expect(
      workspace.members.firstWhere((member) => member.id == 'bot-1').role,
      'Discord bot',
    );
    final guildMember = workspace.memberById('user-1');
    expect(guildMember.displayName, 'Mira Ops');
    expect(guildMember.roleFor('guild-1'), 'Operator');
    expect(guildMember.colorValue, 0xff336699);
    expect(guildMember.avatarUrl, contains('/avatars/user-1/'));
    expect(
      guildMember.avatarUrlFor('guild-1'),
      contains('/guilds/guild-1/users/user-1/avatars/member-avatar.webp'),
    );
    expect(history.messages.map((message) => message.id), ['old', 'new']);
    expect(history.members.single.displayName, 'Mira');
    expect(history.messages.first.embeds.single.title, 'Release status');
    expect(history.messages.first.embeds.single.fields, hasLength(2));
    expect(history.messages.first.mentionsCurrentMember, isTrue);
    expect(history.messages.last.mentionsCurrentMember, isFalse);

    final edited = mapper.message({
      'id': 'new',
      'channel_id': 'channel-1',
      'edited_timestamp': '2026-07-23T02:03:00Z',
    }, fallback: history.messages.last);
    expect(edited.body, 'message new');
    expect(edited.authorId, 'user-1');
    expect(edited.isEdited, isTrue);
    expect(edited.embeds.single.title, 'Release status');
    expect(edited.mentionsCurrentMember, isFalse);

    final retainedMention = mapper.message(
      {
        'id': 'old',
        'channel_id': 'channel-1',
        'edited_timestamp': '2026-07-23T02:04:00Z',
      },
      fallback: history.messages.first,
      currentMemberId: 'bot-1',
    );
    expect(retainedMention.mentionsCurrentMember, isTrue);
  });

  test('mapper builds a direct message inbox with recipient identity', () {
    final workspace = DiscordMapper().workspace(
      currentUser: {'id': 'bot-1', 'username': 'Flucord Bot'},
      guilds: const [],
      channelsByGuild: const {},
      includeDirectMessagesSpace: true,
      directChannels: const [
        {
          'id': 'dm-1',
          'type': 1,
          'recipients': [
            {
              'id': '123456789012345678',
              'username': 'jack',
              'global_name': 'Jack',
              'avatar': 'avatar-hash',
            },
          ],
        },
      ],
    );

    expect(workspace.spaces.single.kind, SpaceKind.directMessages);
    final channel = workspace.channels.single;
    expect(channel.name, 'Jack');
    expect(channel.recipientId, '123456789012345678');
    expect(channel.isDirectMessage, isTrue);
    expect(
      workspace.memberById('123456789012345678').avatarUrl,
      contains('/avatars/123456789012345678/'),
    );
  });
}

Map<String, Object?> _messagePayload({
  required String id,
  required int minute,
  bool mentionBot = false,
}) => {
  'id': id,
  'channel_id': 'channel-1',
  'content': 'message $id',
  'timestamp': '2026-07-23T02:0$minute:00Z',
  'edited_timestamp': null,
  'attachments': <Object?>[],
  'mentions': [
    if (mentionBot) {'id': 'bot-1'},
  ],
  'embeds': [
    {
      'type': 'rich',
      'title': 'Release status',
      'description': 'Native build complete',
      'color': 0x4c9b72,
      'fields': [
        {'name': 'Platform', 'value': 'Windows', 'inline': true},
        {'name': 'Mode', 'value': 'Release', 'inline': true},
      ],
    },
  ],
  'author': {
    'id': 'user-1',
    'username': 'Mira',
    'global_name': null,
    'avatar': 'history-avatar',
  },
};

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<_RecordedRequest> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(
      _RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        body: body,
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
