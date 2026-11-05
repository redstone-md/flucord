import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/message_embed.dart';
import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'chat_image.dart';
import 'message_content_view.dart';
import 'native_inline_video_player.dart';
import 'user_settings_scope.dart';

class MessageEmbedView extends StatelessWidget {
  const MessageEmbedView({
    required this.embed,
    required this.workspace,
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.inlineVideoBuilder = buildNativeInlineVideo,
    super.key,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;

  /// Where the message was sent, whose names the mentions read in.
  final String? spaceId;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final InlineVideoBuilder inlineVideoBuilder;

  /// The card's fill: the text colour, so white on a dark theme, at 3%.
  static const _fillAlpha = 0.03;

  /// The barely raised card every embed in a message sits on.
  static BoxDecoration cardDecoration(FlucordSurfaceTheme surfaces) =>
      BoxDecoration(
        color: surfaces.text.withValues(alpha: _fillAlpha),
        border: Border.all(color: surfaces.border),
        borderRadius: FlucordRadius.medium,
      );

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final accent = embed.colorValue == null
        ? surfaces.border
        : Color(0xff000000 | (embed.colorValue! & 0x00ffffff));
    final showsMedia = UserSettingsScope.displayOf(context).rendersEmbedMedia;
    if (embed.linkedImage case final image? when showsMedia) {
      return _LinkedImage(media: image);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        key: const ValueKey('embed-card'),
        clipBehavior: Clip.antiAlias,
        decoration: cardDecoration(surfaces),
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
                    spaceId: spaceId,
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
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;

  /// Where the message was sent, whose names the mentions read in.
  final String? spaceId;
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
                spaceId: spaceId,
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
                spaceId: spaceId,
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
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbed embed;
  final ChatWorkspace workspace;

  /// Where the message was sent, whose names the mentions read in.
  final String? spaceId;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final sourceName = embed.author?.name ?? embed.provider?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sourceName != null) ...[
          _EmbedSource(
            name: sourceName,
            iconUrl: embed.author?.iconUrl,
            proxyIconUrl: embed.author?.proxyIconUrl,
          ),
          const SizedBox(height: 7),
        ],
        if (embed.title case final title?) ...[
          Text(title, style: _EmbedText.emphasis(context)),
          const SizedBox(height: 5),
        ],
        if (embed.description case final description?)
          MessageContentView(
            body: description,
            workspace: workspace,
            spaceId: spaceId,
            linkLauncher: linkLauncher,
            onSelectChannel: onSelectChannel,
            textStyle: _EmbedText.body(context),
          ),
        if (embed.fields.isNotEmpty) ...[
          const SizedBox(height: 10),
          _EmbedFields(
            fields: embed.fields,
            workspace: workspace,
            spaceId: spaceId,
            linkLauncher: linkLauncher,
            onSelectChannel: onSelectChannel,
          ),
        ],
      ],
    );
  }
}

class _EmbedSource extends StatelessWidget {
  const _EmbedSource({
    required this.name,
    required this.iconUrl,
    required this.proxyIconUrl,
  });

  final String name;
  final String? iconUrl;
  final String? proxyIconUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (proxyIconUrl != null || iconUrl != null) ...[
          _EmbedIcon(url: iconUrl, proxyUrl: proxyIconUrl, size: 20),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.style.copyWith(
              fontWeight: FontWeight.w500,
              color: context.surfaces.text,
            ),
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
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final List<MessageEmbedField> fields;
  final ChatWorkspace workspace;
  final String? spaceId;
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
                  spaceId: spaceId,
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
    required this.spaceId,
    required this.linkLauncher,
    required this.onSelectChannel,
  });

  final MessageEmbedField field;
  final ChatWorkspace workspace;
  final String? spaceId;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(field.name, style: _EmbedText.emphasis(context)),
        const SizedBox(height: 3),
        MessageContentView(
          body: field.value,
          workspace: workspace,
          spaceId: spaceId,
          linkLauncher: linkLauncher,
          onSelectChannel: onSelectChannel,
          textStyle: _EmbedText.body(context),
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
      borderRadius: FlucordRadius.small,
      child: SizedBox.square(
        dimension: 80,
        child: _RemoteEmbedImage(media: media, box: const Size.square(80)),
      ),
    );
  }
}

class _EmbedMediaView extends StatelessWidget {
  const _EmbedMediaView({required this.media});

  static const _bounds = Size(420, 300);

  final MessageEmbedMedia media;

  @override
  Widget build(BuildContext context) {
    final ratio = media.aspectRatio.clamp(0.65, 2.2);
    return ConstrainedBox(
      constraints: BoxConstraints.loose(_bounds),
      child: AspectRatio(
        aspectRatio: ratio,
        child: ClipRRect(
          borderRadius: FlucordRadius.small,
          child: _RemoteEmbedImage(
            media: media,
            box: boxFitting(_bounds, ratio),
          ),
        ),
      ),
    );
  }
}

/// A linked picture on its own, at its own size up to the bounds an
/// attached image has.
class _LinkedImage extends StatelessWidget {
  const _LinkedImage({required this.media});

  static const _bounds = Size(400, 300);

  final MessageEmbedMedia media;

  @override
  Widget build(BuildContext context) {
    final box = boxFitting(
      Size(
        math.min(_bounds.width, media.width?.toDouble() ?? _bounds.width),
        math.min(_bounds.height, media.height?.toDouble() ?? _bounds.height),
      ),
      media.aspectRatio,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: SizedBox.fromSize(
        key: const ValueKey('embed-linked-image'),
        size: box,
        child: ClipRRect(
          borderRadius: FlucordRadius.small,
          child: _RemoteEmbedImage(media: media, box: box),
        ),
      ),
    );
  }
}

class _RemoteEmbedImage extends StatelessWidget {
  const _RemoteEmbedImage({required this.media, required this.box});

  final MessageEmbedMedia media;

  /// The box the picture covers.
  final Size box;

  @override
  Widget build(BuildContext context) {
    // The account's autoplay answer, read here so the flag from any device
    // redraws the embed. A GIF kept still asks the proxy for its png frame,
    // or the cdn's webp form where there is no proxy.
    final plays = UserSettingsScope.displayOf(context).playsGifs;
    final url = media.proxyUrl ?? media.url;
    return Image(
      key: const ValueKey('embed-image'),
      image: _embedImage(
        context,
        address: plays || !_isGif(media) ? url : _stillFrameOf(media),
        isProxied: media.proxyUrl != null,
        size: _covering(box, media.aspectRatio),
      ),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: context.surfaces.surface,
        child: FlucordIcon(
          FlucordIcons.brokenImage,
          size: 20,
          color: context.surfaces.muted,
        ),
      ),
    );
  }
}

/// The small round picture of an embed's author or footer.
class _EmbedIcon extends StatelessWidget {
  const _EmbedIcon({
    required this.url,
    required this.proxyUrl,
    required this.size,
  });

  final String? url;
  final String? proxyUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image(
        key: const ValueKey('embed-icon'),
        image: _embedImage(
          context,
          address: proxyUrl ?? url!,
          isProxied: proxyUrl != null,
          size: Size.square(size),
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// An embed's picture at [address], which asks for [size] when [isProxied],
/// because only a media proxy resizes on request.
ImageProvider _embedImage(
  BuildContext context, {
  required String address,
  required bool isProxied,
  required Size size,
}) => chatImage(
  context,
  size: size,
  addressAt: (width, height) {
    final proxy = isProxied ? Uri.tryParse(address) : null;
    if (proxy == null || !proxy.hasAuthority) return address;
    return proxyAddressAtSize(proxy, width: width, height: height);
  },
);

/// The size a picture of this [ratio] is drawn at to cover [box].
///
/// [BoxFit.cover] crops the longer side, so the shorter side sets the size. A
/// very long picture is treated as less long, so it never asks for a huge file.
Size _covering(Size box, double ratio) {
  final shape = ratio.clamp(0.25, 4.0);
  return shape > box.aspectRatio
      ? Size(box.height * shape, box.height)
      : Size(box.width, box.width / shape);
}

/// Whether the embed's picture is a moving one, judged from the address it
/// is drawn from.
bool _isGif(MessageEmbedMedia media) =>
    (media.proxyUrl ?? media.url).toLowerCase().endsWith('.gif');

/// The first frame of a GIF the account keeps still. Any media proxy serves a
/// png when asked, and Discord's cdn serves the webp form of the same path.
/// Another host has no still form, so its picture is drawn as it is.
String _stillFrameOf(MessageEmbedMedia media) {
  final proxy = Uri.tryParse(media.proxyUrl ?? '');
  if (proxy != null && proxy.hasAuthority) {
    return proxy
        .replace(queryParameters: {...proxy.queryParameters, 'format': 'png'})
        .toString();
  }
  return Uri.tryParse(media.url)?.host == 'cdn.discordapp.com'
      ? cdnStillFrameOf(media.url)
      : media.url;
}

class _EmbedFooterRow extends StatelessWidget {
  const _EmbedFooterRow({required this.footer, required this.timestamp});

  final MessageEmbedFooter? footer;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final iconUrl = footer?.iconUrl;
    final proxyIconUrl = footer?.proxyIconUrl;
    final timestampLabel = timestamp == null ? null : _formatTime(timestamp!);
    return Row(
      children: [
        if (proxyIconUrl != null || iconUrl != null) ...[
          _EmbedIcon(url: iconUrl, proxyUrl: proxyIconUrl, size: 18),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            [?footer?.text, ?timestampLabel].join(' • '),
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.muted,
            ),
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

/// The two text styles inside an embed, on the label role: names and titles
/// one weight step up in the title tier, other text in the body tier.
abstract final class _EmbedText {
  static TextStyle emphasis(BuildContext context) => FlucordTextRole.label.style
      .copyWith(fontWeight: FontWeight.w500, color: context.surfaces.text);

  static TextStyle body(BuildContext context) =>
      FlucordTextRole.label.style.copyWith(color: context.surfaces.bodyText);
}
