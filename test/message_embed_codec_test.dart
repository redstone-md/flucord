import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/message_embed_codec.dart';

void main() {
  test('round-trips the documented Discord embed structure', () {
    final embeds = MessageEmbedCodec.listFrom([
      {
        'type': 'rich',
        'title': 'Deploy complete',
        'description': 'Windows package is ready.',
        'url': 'https://example.test/release',
        'timestamp': '2026-07-23T03:47:00Z',
        'color': 0x4c9b72,
        'author': {
          'name': 'Build service',
          'url': 'https://example.test',
          'icon_url': 'https://cdn.example/author.png',
          'proxy_icon_url': 'https://proxy.example/author.png',
        },
        'provider': {'name': 'Flucord CI', 'url': 'https://example.test/ci'},
        'footer': {
          'text': 'main',
          'icon_url': 'https://cdn.example/footer.png',
        },
        'image': {
          'url': 'https://cdn.example/image.png',
          'proxy_url': 'https://proxy.example/image.png',
          'width': 1200,
          'height': 630,
        },
        'thumbnail': {
          'url': 'https://cdn.example/thumb.png',
          'width': 128,
          'height': 128,
        },
        'video': {
          'url': 'https://video.example/release.mp4',
          'width': 1920,
          'height': 1080,
        },
        'fields': [
          {'name': 'Tests', 'value': '91 passed', 'inline': true},
          {'name': 'Artifact', 'value': 'flucord.exe', 'inline': false},
        ],
      },
    ]);

    final decoded = MessageEmbedCodec.decode(
      MessageEmbedCodec.encode(embeds),
    ).single;
    expect(decoded.title, 'Deploy complete');
    expect(decoded.timestamp?.toUtc().hour, 3);
    expect(decoded.author?.name, 'Build service');
    expect(decoded.provider?.name, 'Flucord CI');
    expect(decoded.image?.proxyUrl, 'https://proxy.example/image.png');
    expect(decoded.thumbnail?.aspectRatio, 1);
    expect(decoded.video?.width, 1920);
    expect(decoded.fields, hasLength(2));
    expect(decoded.fields.first.isInline, isTrue);
  });

  test('ignores malformed optional embed objects', () {
    final embed = MessageEmbedCodec.listFrom([
      {
        'type': 'link',
        'author': <String, Object?>{},
        'image': {'url': ''},
        'fields': [null, 'invalid'],
      },
    ]).single;

    expect(embed.author, isNull);
    expect(embed.image, isNull);
    expect(embed.fields, isEmpty);
  });
}
