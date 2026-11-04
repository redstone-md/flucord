import 'package:flutter/material.dart';

import '../../application/active_friends.dart';
import '../../domain/chat_models.dart';
import '../../domain/monogram.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'art_tile.dart';
import 'flucord_button.dart';
import 'optically_centred.dart';
import 'remote_identity_image.dart';

/// Formats how long an activity has run or has left, in whole minutes:
/// "35 min", "2 h", "1 h 20 min". The profile card and the Active now column
/// both read it, so the two never disagree.
abstract final class ActivityElapsed {
  /// [span] in hours and minutes, or null under a minute, where there is no
  /// time worth reading yet.
  static String? format(Duration span) {
    final hours = span.inHours;
    final minutes = span.inMinutes % 60;
    if (hours == 0) return minutes == 0 ? null : '$minutes min';
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  /// How long the activity has run at [now], or null without a start.
  static String? since(ActivityTimestamps? timestamps, DateTime now) =>
      switch (timestamps?.elapsedAt(now)) {
        final span? => format(span),
        null => null,
      };

  /// The timing, or null when the activity carries no usable stamp: the
  /// time run so far bare ("1 h 20 min"), a countdown with "left".
  ///
  /// R07's `isCountDown` decides the direction: a track that ends counts up
  /// from its start, while a match with an end counts down to it.
  static String? line(ActivityTimestamps? timestamps, DateTime now) {
    if (timestamps == null) return null;
    final remaining = timestamps.remainingAt(now);
    final elapsed = timestamps.elapsedAt(now);
    if (remaining != null && (timestamps.isCountDown || elapsed == null)) {
      return switch (format(remaining)) {
        final text? => '$text left',
        null => null,
      };
    }
    return elapsed == null ? null : format(elapsed);
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

/// What somebody is doing, as the profile card and the full profile draw it:
/// the artwork, and beside it the kind ("Playing"), the name, the details
/// with the time, and the state.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    required this.activity,
    required this.now,
    this.artSize = ActivityFrame.cardArt,
    super.key,
  });

  final UserActivity activity;

  /// Captured by the caller rather than read here, so the card renders the
  /// same value twice in a row and a test can pin the clock.
  final DateTime now;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final party = activity.party;
    final state = activity.state;
    final details = [
      ?activity.details,
      ?ActivityElapsed.line(activity.timestamps, now),
    ].join(' · ');
    final verb = activity.type.verb;
    return ActivityFrame(
      key: const ValueKey('activity-card'),
      art: _ActivityArtwork(activity: activity, size: artSize),
      kind: verb.isEmpty ? 'Activity' : verb,
      title: activity.name,
      lines: [
        if (details.isNotEmpty) details,
        if (state != null)
          party != null && party.hasSize
              ? '$state (${party.currentSize} of ${party.maxSize})'
              : state,
      ],
    );
  }
}

/// The voice channel somebody sits in: the server's art, "In voice", the
/// channel, and the server with how many people are there. [onJoin] puts a
/// Join button at the end of the row.
class VoiceRoomCard extends StatelessWidget {
  const VoiceRoomCard({
    required this.room,
    this.onJoin,
    this.artSize = ActivityFrame.cardArt,
    super.key,
  });

  final ActiveFriendRoom room;
  final VoidCallback? onJoin;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final space = room.space;
    return ActivityFrame(
      key: const ValueKey('voice-room-card'),
      art: ArtTile(
        url: space.iconUrl,
        monogram: space.monogram,
        color: Color(space.colorValue),
        size: artSize,
      ),
      kind: 'In voice',
      title: room.channel.name,
      lines: ['in ${space.name} · ${peopleCount(room.people.length)}'],
      trailing: switch (onJoin) {
        final join? => FlucordButton(
          key: const ValueKey('voice-room-join'),
          label: 'Join',
          onPressed: join,
        ),
        null => null,
      },
    );
  }
}

/// "1 person", "3 people".
String peopleCount(int count) => count == 1 ? '1 person' : '$count people';

/// The card every activity is drawn in: [art] 8 in from the edge, and beside
/// it a small [kind] caption over the [title] and the caption [lines], the
/// block centred on the art by eye. [trailing] sits at the row's end.
///
/// The art has [FlucordRadius.medium] corners 8 in, so the card is
/// [FlucordRadius.framed] around it.
class ActivityFrame extends StatelessWidget {
  const ActivityFrame({
    required this.art,
    required this.kind,
    required this.title,
    this.lines = const [],
    this.trailing,
    super.key,
  });

  /// The art's size in the profile card.
  static const cardArt = 56.0;

  /// The art's size in the full profile window.
  static const windowArt = 64.0;

  static const _padding = 8.0;

  final Widget art;
  final String kind;
  final String title;
  final List<String> lines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final caption = FlucordTextRole.caption.style.copyWith(
      color: surfaces.muted,
    );
    Widget line(String text, TextStyle style) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    final trailing = this.trailing;
    return Container(
      padding: const EdgeInsets.fromLTRB(_padding, _padding, 12, _padding),
      decoration: BoxDecoration(
        color: surfaces.inset,
        borderRadius: FlucordRadius.framed,
        border: Border.all(color: surfaces.border),
      ),
      child: Row(
        children: [
          art,
          const SizedBox(width: 12),
          Expanded(
            child: OpticallyCentred(
              lines: [
                FlucordTextRole.caption,
                FlucordTextRole.label,
                for (final _ in lines) FlucordTextRole.caption,
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  line(kind, caption),
                  const SizedBox(height: 2),
                  line(
                    title,
                    FlucordTextRole.label.strong.copyWith(color: surfaces.text),
                  ),
                  for (final text in lines) ...[
                    const SizedBox(height: 2),
                    line(text, caption),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }
}

/// The large asset, or the activity's monogram where there is none, with
/// the small asset badged over its corner.
class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({required this.activity, required this.size});

  final UserActivity activity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final assets = activity.assets;
    final largeText = assets?.largeText;
    final smallText = assets?.smallText;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Tooltip(
            message: largeText ?? '',
            excludeFromSemantics: largeText == null,
            child: ArtTile(
              url: assets?.largeImageUrl,
              imageKey: const ValueKey('activity-large-image'),
              monogram: monogramOf(activity.name),
              color: context.surfaces.raised,
              size: size,
            ),
          ),
          if (assets?.smallImageUrl case final url?)
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
}
