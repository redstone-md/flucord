import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
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
      style: TextStyle(fontSize: FlucordType.fitting(size)),
      semanticsLabel: emoji.isCustom ? ':${emoji.name}:' : emoji.name,
    );
  }
}

/// What the line under a member's name says, the way Discord's member list
/// puts it: a kind icon for what they are doing, then their custom status if
/// they set one, or else the activity's name with no verb.
@immutable
final class ActivitySummary {
  const ActivitySummary._({
    required this.text,
    this.kind,
    this.emoji,
    this.more = 0,
  });

  /// The summary of [activities], or null when there is nothing to show.
  ///
  /// [inVoice] stands in when the member is doing nothing else: a speaker
  /// and "In voice".
  static ActivitySummary? of(
    Iterable<UserActivity> activities, {
    bool inVoice = false,
  }) {
    UserActivity? custom;
    final doing = <UserActivity>[];
    for (final activity in activities) {
      switch (activity.type) {
        case ActivityType.hangStatus:
          continue;
        case ActivityType.customStatus:
          custom ??= activity;
        default:
          doing.add(activity);
      }
    }
    final main = doing.firstOrNull;
    final kind = main != null
        ? _kindIcon(main.type)
        : inVoice
        ? FlucordIcons.voiceChannel
        : null;
    // The activities past the main one, whose icon the line shows.
    final more = main == null ? 0 : doing.length - 1;
    final status = custom?.state ?? '';
    if (custom != null && (status.isNotEmpty || custom.emoji != null)) {
      return ActivitySummary._(
        kind: kind,
        emoji: custom.emoji,
        text: status,
        more: more,
      );
    }
    if (main != null) {
      return ActivitySummary._(kind: kind, text: main.subject, more: more);
    }
    if (inVoice) return ActivitySummary._(kind: kind, text: 'In voice');
    return null;
  }

  static FlucordIconData? _kindIcon(ActivityType type) => switch (type) {
    ActivityType.playing => FlucordIcons.game,
    ActivityType.streaming => FlucordIcons.streaming,
    ActivityType.listening => FlucordIcons.listening,
    ActivityType.watching => FlucordIcons.watching,
    ActivityType.competing => FlucordIcons.competing,
    ActivityType.customStatus ||
    ActivityType.hangStatus ||
    ActivityType.unrecognised => null,
  };

  /// What the member is doing, drawn first. Null for a custom status alone.
  final FlucordIconData? kind;
  final ActivityEmoji? emoji;
  final String text;

  /// How many activities there are beyond the one named.
  final int more;
}

/// An [ActivitySummary] on one caption line, cut with an ellipsis. The text
/// is [color], or muted when it is not given.
class ActivitySummaryLine extends StatelessWidget {
  const ActivitySummaryLine({required this.summary, this.color, super.key});

  final ActivitySummary summary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final style = FlucordTextRole.caption.style.copyWith(
      color: color ?? surfaces.muted,
    );
    final ActivitySummary(:kind, :emoji, :text, :more) = summary;
    const gap = SizedBox(width: 4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kind != null) ...[
          FlucordIcon(kind, size: FlucordType.caption, color: surfaces.success),
          gap,
        ],
        if (emoji != null) ...[
          ActivityEmojiView(emoji: emoji, size: FlucordType.body),
          if (text.isNotEmpty) gap,
        ],
        // Flexible rather than Expanded: in a narrow panel the icons and the
        // count keep their size and the text is what gives way.
        if (text.isNotEmpty)
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        if (more > 0) ...[gap, Text('+$more', style: style)],
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
        borderRadius: FlucordRadius.medium,
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
                  style: FlucordTextRole.caption.strong,
                ),
                for (final line in lines) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: FlucordType.caption,
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
              borderRadius: FlucordRadius.medium,
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
