import 'dart:convert';

import '../domain/message_embed.dart';

final class MessageEmbedCodec {
  const MessageEmbedCodec._();

  static String encode(List<MessageEmbed> embeds) =>
      jsonEncode(embeds.map(_toMap).toList(growable: false));

  static List<MessageEmbed> decode(String source) =>
      listFrom(jsonDecode(source));

  static List<MessageEmbed> listFrom(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((raw) => fromMap(raw.cast<String, Object?>()))
          .toList(growable: false);

  static MessageEmbed fromMap(Map<String, Object?> raw) => MessageEmbed(
    type: raw['type'] as String? ?? 'rich',
    title: raw['title'] as String?,
    description: raw['description'] as String?,
    url: raw['url'] as String?,
    colorValue: raw['color'] as int?,
    timestamp: _timestamp(raw['timestamp']),
    footer: _footer(raw['footer']),
    image: _media(raw['image']),
    thumbnail: _media(raw['thumbnail']),
    video: _media(raw['video']),
    provider: _provider(raw['provider']),
    author: _author(raw['author']),
    fields: (raw['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((field) => field.cast<String, Object?>())
        .map(
          (field) => MessageEmbedField(
            name: field['name'] as String? ?? '',
            value: field['value'] as String? ?? '',
            isInline: field['inline'] == true,
          ),
        )
        .toList(growable: false),
  );

  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static MessageEmbedMedia? _media(Object? value) {
    final raw = _map(value);
    final url = raw?['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return MessageEmbedMedia(
      url: url,
      proxyUrl: raw?['proxy_url'] as String?,
      width: raw?['width'] as int?,
      height: raw?['height'] as int?,
    );
  }

  static MessageEmbedFooter? _footer(Object? value) {
    final raw = _map(value);
    final text = raw?['text'] as String?;
    if (text == null || text.isEmpty) return null;
    return MessageEmbedFooter(
      text: text,
      iconUrl: raw?['icon_url'] as String?,
      proxyIconUrl: raw?['proxy_icon_url'] as String?,
    );
  }

  static MessageEmbedProvider? _provider(Object? value) {
    final raw = _map(value);
    final name = raw?['name'] as String?;
    if (name == null || name.isEmpty) return null;
    return MessageEmbedProvider(name: name, url: raw?['url'] as String?);
  }

  static MessageEmbedAuthor? _author(Object? value) {
    final raw = _map(value);
    final name = raw?['name'] as String?;
    if (name == null || name.isEmpty) return null;
    return MessageEmbedAuthor(
      name: name,
      url: raw?['url'] as String?,
      iconUrl: raw?['icon_url'] as String?,
      proxyIconUrl: raw?['proxy_icon_url'] as String?,
    );
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static Map<String, Object?> _toMap(MessageEmbed embed) => {
    'type': embed.type,
    'title': embed.title,
    'description': embed.description,
    'url': embed.url,
    'color': embed.colorValue,
    'timestamp': embed.timestamp?.toUtc().toIso8601String(),
    'footer': _footerToMap(embed.footer),
    'image': _mediaToMap(embed.image),
    'thumbnail': _mediaToMap(embed.thumbnail),
    'video': _mediaToMap(embed.video),
    'provider': _providerToMap(embed.provider),
    'author': _authorToMap(embed.author),
    'fields': [
      for (final field in embed.fields)
        {'name': field.name, 'value': field.value, 'inline': field.isInline},
    ],
  };

  static Map<String, Object?>? _mediaToMap(MessageEmbedMedia? media) =>
      media == null
      ? null
      : {
          'url': media.url,
          'proxy_url': media.proxyUrl,
          'width': media.width,
          'height': media.height,
        };

  static Map<String, Object?>? _footerToMap(MessageEmbedFooter? footer) =>
      footer == null
      ? null
      : {
          'text': footer.text,
          'icon_url': footer.iconUrl,
          'proxy_icon_url': footer.proxyIconUrl,
        };

  static Map<String, Object?>? _providerToMap(MessageEmbedProvider? provider) =>
      provider == null ? null : {'name': provider.name, 'url': provider.url};

  static Map<String, Object?>? _authorToMap(MessageEmbedAuthor? author) =>
      author == null
      ? null
      : {
          'name': author.name,
          'url': author.url,
          'icon_url': author.iconUrl,
          'proxy_icon_url': author.proxyIconUrl,
        };
}
