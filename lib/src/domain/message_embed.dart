final class MessageEmbed {
  MessageEmbed({
    required this.type,
    this.title,
    this.description,
    this.url,
    this.colorValue,
    this.timestamp,
    this.footer,
    this.image,
    this.thumbnail,
    this.video,
    this.provider,
    this.author,
    List<MessageEmbedField> fields = const [],
  }) : fields = List.unmodifiable(fields);

  final String type;
  final String? title;
  final String? description;
  final String? url;
  final int? colorValue;
  final DateTime? timestamp;
  final MessageEmbedFooter? footer;
  final MessageEmbedMedia? image;
  final MessageEmbedMedia? thumbnail;
  final MessageEmbedMedia? video;
  final MessageEmbedProvider? provider;
  final MessageEmbedAuthor? author;
  final List<MessageEmbedField> fields;
}

final class MessageEmbedMedia {
  const MessageEmbedMedia({
    required this.url,
    this.proxyUrl,
    this.width,
    this.height,
  });

  final String url;
  final String? proxyUrl;
  final int? width;
  final int? height;

  double get aspectRatio {
    final mediaWidth = width;
    final mediaHeight = height;
    if (mediaWidth == null || mediaHeight == null || mediaHeight == 0) {
      return 16 / 9;
    }
    return mediaWidth / mediaHeight;
  }
}

final class MessageEmbedFooter {
  const MessageEmbedFooter({
    required this.text,
    this.iconUrl,
    this.proxyIconUrl,
  });

  final String text;
  final String? iconUrl;
  final String? proxyIconUrl;
}

final class MessageEmbedProvider {
  const MessageEmbedProvider({required this.name, this.url});

  final String name;
  final String? url;
}

final class MessageEmbedAuthor {
  const MessageEmbedAuthor({
    required this.name,
    this.url,
    this.iconUrl,
    this.proxyIconUrl,
  });

  final String name;
  final String? url;
  final String? iconUrl;
  final String? proxyIconUrl;
}

final class MessageEmbedField {
  const MessageEmbedField({
    required this.name,
    required this.value,
    this.isInline = false,
  });

  final String name;
  final String value;
  final bool isInline;
}
