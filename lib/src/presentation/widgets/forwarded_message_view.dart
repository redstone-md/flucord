import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'message_attachment_view.dart';
import 'message_content_view.dart';
import 'message_embed_view.dart';
import 'message_sticker_view.dart';

class ForwardedMessageView extends StatelessWidget {
  const ForwardedMessageView({
    required this.snapshot,
    required this.reference,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
    super.key,
  });

  final MessageSnapshot snapshot;
  final MessageReference reference;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Container(
      key: const ValueKey('forwarded-message'),
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: context.surfaces.border, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SourceLine(source: source, onSelectChannel: onSelectChannel),
          if (snapshot.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            MessageContentView(
              body: snapshot.body,
              workspace: workspace,
              linkLauncher: linkLauncher,
              onSelectChannel: onSelectChannel,
            ),
          ],
          for (final attachment in snapshot.attachments)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: MessageAttachmentView(attachment: attachment),
            ),
          for (var index = 0; index < snapshot.embeds.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: MessageEmbedView(
                key: ValueKey('forwarded-embed-$index'),
                embed: snapshot.embeds[index],
                workspace: workspace,
                linkLauncher: linkLauncher,
                onSelectChannel: onSelectChannel,
              ),
            ),
          if (snapshot.stickers.isNotEmpty)
            MessageStickerStrip(stickers: snapshot.stickers),
          if (snapshot.components.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Interactive components are unavailable in this snapshot.',
                key: const ValueKey('forwarded-components-unavailable'),
                style: TextStyle(color: context.surfaces.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  _ForwardSource get _source {
    final channelId = reference.channelId;
    final channel = channelId == null
        ? null
        : workspace.channelOrNull(channelId);
    if (channel == null) {
      return const _ForwardSource(label: 'Forwarded message');
    }
    final space = workspace.spaceById(channel.spaceId);
    final channelLabel = space.isDirectMessages
        ? channel.name
        : '#${channel.name}';
    return _ForwardSource(
      label: 'Forwarded message · $channelLabel · ${space.name}',
      channelId: channel.id,
    );
  }
}

final class _ForwardSource {
  const _ForwardSource({required this.label, this.channelId});

  final String label;
  final String? channelId;
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.source, required this.onSelectChannel});

  final _ForwardSource source;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('forwarded-message-source'),
    onTap: source.channelId == null
        ? null
        : () => onSelectChannel(source.channelId!),
    borderRadius: BorderRadius.circular(3),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forward, size: 13, color: context.surfaces.muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
