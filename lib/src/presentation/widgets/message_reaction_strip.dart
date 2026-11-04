import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'remote_identity_image.dart';
import 'user_settings_scope.dart';

class MessageReactionStrip extends StatelessWidget {
  const MessageReactionStrip({
    required this.message,
    required this.workspace,
    required this.onToggle,
    required this.onShowDetails,
    super.key,
  });

  final ChatMessage message;
  final ChatWorkspace workspace;
  final ValueChanged<MessageReaction> onToggle;
  final ValueChanged<MessageReaction> onShowDetails;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final reaction in message.reactions)
        _ReactionChip(
          message: message,
          reaction: reaction,
          workspace: workspace,
          onToggle: () => onToggle(reaction),
          onShowDetails: () => onShowDetails(reaction),
        ),
    ],
  );
}

class ReactionGlyph extends StatelessWidget {
  const ReactionGlyph({
    required this.reaction,
    required this.workspace,
    required this.channelId,
    this.size = 16,
    super.key,
  });

  final MessageReaction reaction;
  final ChatWorkspace workspace;
  final String channelId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final emoji = _guildEmoji();
    if (emoji == null) {
      return Text(
        reaction.emojiName,
        style: TextStyle(fontSize: FlucordType.fitting(size - 4)),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: FlucordRadius.small,
        child: RemoteIdentityImage(
          url: emoji.imageUrl,
          animatesOnHover: false,
          // The account's animate-emoji answer, read here so the flag from
          // any device redraws the strip.
          playsAnimations: UserSettingsScope.displayOf(
            context,
          ).playsAnimatedEmoji,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: Center(
              child: Text(
                emoji.name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: FlucordType.fitting(size / 2),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  GuildEmoji? _guildEmoji() {
    final id = reaction.emojiId;
    if (id == null) return null;
    final spaceId = workspace.channelById(channelId).spaceId;
    for (final emoji in workspace.emojisFor(spaceId)) {
      if (emoji.id == id) return emoji;
    }
    return null;
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.message,
    required this.reaction,
    required this.workspace,
    required this.onToggle,
    required this.onShowDetails,
  });

  final ChatMessage message;
  final MessageReaction reaction;
  final ChatWorkspace workspace;
  final VoidCallback onToggle;
  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final selected =
        reaction.reactedByCurrentUser || reaction.burstByCurrentUser;
    final burstColor = reaction.burstColorValues.firstOrNull;
    return Semantics(
      // Its own node, so a screen reader reaches each reaction as a button
      // and the row's text does not swallow it.
      container: true,
      label: '${reaction.emojiName} reaction, ${reaction.count}',
      button: true,
      toggled: selected,
      onTap: onToggle,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'View reaction details'):
            onShowDetails,
      },
      excludeSemantics: true,
      child: Tooltip(
        message: 'Click to toggle · Right-click for details',
        child: Material(
          color: selected
              ? context.surfaces.brand.withValues(alpha: 0.16)
              : context.surfaces.inset,
          borderRadius: FlucordRadius.small,
          child: InkWell(
            onTap: onToggle,
            onSecondaryTap: onShowDetails,
            borderRadius: FlucordRadius.small,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected
                      ? context.surfaces.brand.withValues(alpha: 0.65)
                      : context.surfaces.border,
                ),
                borderRadius: FlucordRadius.small,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KeyedSubtree(
                    key: ValueKey(
                      'reaction-custom-${message.id}-${reaction.emojiId}',
                    ),
                    child: ReactionGlyph(
                      reaction: reaction,
                      workspace: workspace,
                      channelId: message.channelId,
                    ),
                  ),
                  if (reaction.burstCount > 0) ...[
                    const SizedBox(width: 4),
                    FlucordIcon(
                      FlucordIcons.superReaction,
                      size: 10,
                      color: burstColor == null
                          ? context.surfaces.warning
                          : Color(burstColor),
                    ),
                  ],
                  const SizedBox(width: 5),
                  Text(
                    '${reaction.count}',
                    style: const TextStyle(
                      fontSize: FlucordType.caption,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
