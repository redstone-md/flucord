import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';

void main() {
  test('sends the exact documented voice-message multipart payload', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-voice-upload-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}voice.ogg');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    final transport = _RecordingTransport();
    final client = DiscordApiClient(botToken: 'token', transport: transport);
    addTearDown(client.close);

    await client.createVoiceMessage(
      channelId: 'channel-1',
      voiceMessage: PendingVoiceMessage(
        name: 'voice.ogg',
        path: file.path,
        size: 4,
        durationSecs: 1.5,
        waveform: 'AECA/w==',
      ),
      nonce: 'voice-native-1',
      enforceNonce: true,
    );

    final request = transport.request!;
    expect(request.uri.path, '/api/v10/channels/channel-1/messages');
    expect(request.headers['content-type'], startsWith('multipart/form-data'));
    final body = utf8.decode(request.body);
    expect(body, contains('Content-Type: audio/ogg'));
    final payload = _payloadJson(body);
    expect(payload, {
      'flags': DiscordMessageFlag.voiceMessage.bit,
      'nonce': 'voice-native-1',
      'enforce_nonce': true,
      'attachments': [
        {
          'id': 0,
          'filename': 'voice.ogg',
          'duration_secs': 1.5,
          'waveform': 'AECA/w==',
        },
      ],
    });
    expect(payload.containsKey('content'), isFalse);
  });
}

Map<String, Object?> _payloadJson(String multipart) {
  const marker = 'Content-Type: application/json\r\n\r\n';
  final start = multipart.indexOf(marker) + marker.length;
  final end = multipart.indexOf('\r\n--', start);
  return (jsonDecode(multipart.substring(start, end)) as Map)
      .cast<String, Object?>();
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordedRequest? request;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    request = _RecordedRequest(uri: uri, headers: headers, body: body!);
    return const DiscordHttpResponse(
      statusCode: 200,
      headers: {},
      body:
          '{"id":"voice-1","channel_id":"channel-1",'
          '"author":{"id":"bot-1"},"content":"",'
          '"timestamp":"2026-07-24T08:00:00Z","flags":8192,'
          '"attachments":[]}',
    );
  }

  @override
  void close() {}
}
