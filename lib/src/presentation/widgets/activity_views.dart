import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

/// Formats the durations a rich presence card shows.
abstract final class ActivityElapsed {
  /// `H:MM:SS` past an hour, `MM:SS` below it — the shape Discord uses, which
  /// keeps a two-minute track from reading as `00:02:11`.
  static String format(Duration span) {
    final seconds = span.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    final hours = seconds ~/ 3600;
    final rest = seconds % 60;
    final body =
        '${minutes.toString().padLeft(2, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
    return hours > 0 ? '$hours:$body' : body;
  }

  /// The timing line, or null when the activity carries no usable stamp.
  ///
  /// R07's `isCountDown` decides the direction: a track that ends counts up
  /// from its start, while a match with an end counts down to it.
  static String? line(ActivityTimestamps? timestamps, DateTime now) {
    if (timestamps == null) return null;
    if (timestamps.isCountDown) {
      final remaining = timestamps.remainingAt(now);
      if (remaining != null) return '${format(remaining)} left';
    }
    final elapsed = timestamps.elapsedAt(now);
    if (elapsed != null) return '${format(elapsed)} elapsed';
    final remaining = timestamps.remainingAt(now);
    return remaining == null ? null : '${format(remaining)} left';
  }
}

/// The emoji beside a custom status: a glyph for Unicode, artwork for custom.
class ActivityEmojiView extends StatelessWidget {
  const ActivityEmojiView({required this.emoji, this.size = 14, super.key});

  final ActivityEmoji emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = emoji.imageUrl;
    if (emoji.isCustom && url != null) {
      return SizedBox.square(
        dimension: size,
        child: RemoteIdentityImage(
          url: url,
          imageKey: ValueKey('activity-emoji-${emoji.id}'),
          fallback: const SizedBox.shrink(),
        ),
      );
    }
    return Text(
      emoji.name,
      style: TextStyle(fontSize: size),
      semanticsLabel: emoji.isCustom ? ':${emoji.name}:' : emoji.name,
    );
  }
}

/// The one-line activity summary shown under a name in a member row.
class ActivitySummaryLine extends StatelessWidget {
  const ActivitySummaryLine({
    required this.activity,
    this.fontSize = 10,
    this.color,
    super.key,
  });

  final UserActivity activity;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final emoji = activity.emoji;
    final text = activity.summary;
    final style = TextStyle(
      color: color ?? context.surfaces.muted,
      fontSize: fontSize,
    );
    if (emoji == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActivityEmojiView(emoji: emoji, size: fontSize + 2),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          // Flexible rather than Expanded: in a narrow panel the emoji keeps
          // its size and the sentence is what gives way, which is the only way
          // the row can shrink without overflowing.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ],
    );
  }
}

/// The rich presence block Discord draws on a profile: artwork, the three text
/// lines and the timing line.
class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.activity, required this.now, super.key});

  final UserActivity activity;

  /// Captured by the caller rather than read here, so the card renders the
  /// same value twice in a row and a test can pin the clock.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final assets = activity.assets;
    final timing = ActivityElapsed.line(activity.timestamps, now);
    final party = activity.party;
    final state = activity.state;
    final lines = <String>[
      ?activity.details,
      if (state != null)
        party != null && party.hasSize
            ? '$state (${party.currentSize} of ${party.maxSize})'
            : state,
      ?timing,
    ];
    return Container(
      key: const ValueKey('activity-card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (assets?.largeImageUrl case final url?) ...[
            _ActivityArtwork(
              largeUrl: url,
              smallUrl: assets?.smallImageUrl,
              largeText: assets?.largeText,
              smallText: assets?.smallText,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The large asset with the small one badged over its corner.
class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({
    required this.largeUrl,
    this.smallUrl,
    this.largeText,
    this.smallText,
  });

  final String largeUrl;
  final String? smallUrl;
  final String? largeText;
  final String? smallText;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 56,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Tooltip(
            message: largeText ?? '',
            excludeFromSemantics: largeText == null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: RemoteIdentityImage(
                url: largeUrl,
                imageKey: const ValueKey('activity-large-image'),
                fallback: ColoredBox(color: context.surfaces.raised),
              ),
            ),
          ),
        ),
        if (smallUrl case final url?)
          Positioned(
            right: -4,
            bottom: -4,
            child: Tooltip(
              message: smallText ?? '',
              excludeFromSemantics: smallText == null,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.surfaces.inset, width: 2),
                ),
                child: ClipOval(
                  child: RemoteIdentityImage(
                    url: url,
                    imageKey: const ValueKey('activity-small-image'),
                    fallback: ColoredBox(color: context.surfaces.raised),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
