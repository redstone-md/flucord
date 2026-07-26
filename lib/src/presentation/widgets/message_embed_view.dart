import 'package:flutter/material.dart';

import '../../domain/message_embed.dart';
import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'message_content_view.dart';
import 'native_inline_video_player.dart';
import 'user_settings_scope.dart';

class MessageEmbedView extends StatelessWidget {
  const MessageEmbedView({
    required this.embed,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.inlineVideoBuilder = buildNativeInlineVideo,
    super.key,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final InlineVideoBuilder inlineVideoBuilder;

  @override
  Widget build(BuildContext context) {
    final accent = embed.colorValue == null
        ? context.surfaces.border
        : Color(0xff000000 | (embed.colorValue! & 0x00ffffff));
    final showsMedia = UserSettingsScope.displayOf(context).rendersEmbedMedia;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.surfaces.inset,
          border: Border.all(color: context.surfaces.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(
                key: const ValueKey('embed-accent'),
                color: accent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _EmbedTop(
                    embed: embed,
                    workspace: workspace,
                    linkLauncher: linkLauncher,
                    onSelectChannel: onSelectChannel,
                  ),
                  if (showsMedia) ...[
                    if (embed.video case final video?) ...[
                      const SizedBox(height: 10),
                      inlineVideoBuilder(
                        key: ValueKey(
                          'embed-video-${video.proxyUrl ?? video.url}',
                        ),
                        url: video.proxyUrl ?? video.url,
                        aspectRatio: video.aspectRatio,
                      ),
                    ] else if (embed.image case final image?) ...[
                      const SizedBox(height: 10),
                      _EmbedMediaView(media: image),
                    ],
                  ],
                  if (embed.footer != null || embed.timestamp != null) ...[
                    const SizedBox(height: 10),
                    _EmbedFooterRow(
                      footer: embed.footer,
                      timestamp: embed.timestamp,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbedTop extends StatelessWidget {
  const _EmbedTop({
    required this.embed,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    // A thumbnail is embed media too, so it answers to the same setting as
    // the large image below it rather than surviving as a smaller version.
    final thumbnail = UserSettingsScope.displayOf(context).rendersEmbedMedia
        ? embed.thumbnail
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (thumbnail != null && constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EmbedTextContent(
                embed: embed,
                workspace: workspace,
                linkLauncher: linkLauncher,
                onSelectChannel: onSelectChannel,
              ),
              const SizedBox(height: 10),
              _EmbedThumbnail(media: thumbnail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EmbedTextContent(
                embed: embed,
                workspace: workspace,
                linkLauncher: linkLauncher,
                onSelectChannel: onSelectChannel,
              ),
            ),
            if (thumbnail != null) ...[
              const SizedBox(width: 12),
              _EmbedThumbnail(media: thumbnail),
            ],
          ],
        );
      },
    );
  }
}

class _EmbedTextContent extends StatelessWidget {
  const _EmbedTextContent({
    required this.embed,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final sourceName = embed.author?.name ?? embed.provider?.name;
    final sourceIcon = embed.author?.proxyIconUrl ?? embed.author?.iconUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sourceName != null) ...[
          _EmbedSource(name: sourceName, iconUrl: sourceIcon),
          const SizedBox(height: 7),
        ],
        if (embed.title case final title?) ...[
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
        ],
        if (embed.description case final description?)
          MessageContentView(
            body: description,
            workspace: workspace,
            linkLauncher: linkLauncher,
            onSelectChannel: onSelectChannel,
            textStyle: const TextStyle(fontSize: 12, height: 1.35),
          ),
        if (embed.fields.isNotEmpty) ...[
          const SizedBox(height: 10),
          _EmbedFields(
            fields: embed.fields,
            workspace: workspace,
            linkLauncher: linkLauncher,
            onSelectChannel: onSelectChannel,
          ),
        ],
      ],
    );
  }
}

class _EmbedSource extends StatelessWidget {
  const _EmbedSource({required this.name, required this.iconUrl});

  final String name;
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconUrl != null) ...[
          ClipOval(
            child: Image.network(
              iconUrl!,
              width: 20,
              height: 20,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _EmbedFields extends StatelessWidget {
  const _EmbedFields({
    required this.fields,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final List<MessageEmbedField> fields;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 420
            ? 3
            : constraints.maxWidth >= 260
            ? 2
            : 1;
        const spacing = 10.0;
        final inlineWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: [
            for (var index = 0; index < fields.length; index++)
              SizedBox(
                key: ValueKey('embed-field-$index'),
                width: fields[index].isInline
                    ? inlineWidth
                    : constraints.maxWidth,
                child: _EmbedFieldView(
                  field: fields[index],
                  workspace: workspace,
                  linkLauncher: linkLauncher,
                  onSelectChannel: onSelectChannel,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmbedFieldView extends StatelessWidget {
  const _EmbedFieldView({
    required this.field,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbedField field;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.name,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        MessageContentView(
          body: field.value,
          workspace: workspace,
          linkLauncher: linkLauncher,
          onSelectChannel: onSelectChannel,
          textStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _EmbedThumbnail extends StatelessWidget {
  const _EmbedThumbnail({required this.media});

  final MessageEmbedMedia media;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: 80,
        child: _RemoteEmbedImage(media: media),
      ),
    );
  }
}

class _EmbedMediaView extends StatelessWidget {
  const _EmbedMediaView({required this.media});

  final MessageEmbedMedia media;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 300),
      child: AspectRatio(
        aspectRatio: media.aspectRatio.clamp(0.65, 2.2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _RemoteEmbedImage(media: media),
        ),
      ),
    );
  }
}

class _RemoteEmbedImage extends StatelessWidget {
  const _RemoteEmbedImage({required this.media});

  final MessageEmbedMedia media;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      key: const ValueKey('embed-image'),
      media.proxyUrl ?? media.url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: context.surfaces.surface,
        child: Icon(
          Icons.broken_image_outlined,
          size: 20,
          color: context.surfaces.muted,
        ),
      ),
    );
  }
}

class _EmbedFooterRow extends StatelessWidget {
  const _EmbedFooterRow({required this.footer, required this.timestamp});

  final MessageEmbedFooter? footer;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final iconUrl = footer?.proxyIconUrl ?? footer?.iconUrl;
    final timestampLabel = timestamp == null ? null : _formatTime(timestamp!);
    return Row(
      children: [
        if (iconUrl != null) ...[
          ClipOval(
            child: Image.network(
              iconUrl,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            [?footer?.text, ?timestampLabel].join(' • '),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.surfaces.muted, fontSize: 10),
          ),
        ),
      ],
    );
  }

  static String _formatTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
