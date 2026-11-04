import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/active_friends.dart';
import '../../domain/chat_models.dart';
import '../../domain/monogram.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'art_tile.dart';
import 'member_avatar.dart';
import 'overlapping_faces.dart';

/// The Friends page's right column: one card per friend who is playing,
/// listening, watching or sitting in voice.
class ActiveNowColumn extends StatefulWidget {
  const ActiveNowColumn({
    required this.friends,
    required this.onOpenRoom,
    this.now,
    super.key,
  });

  static const width = 340.0;

  final List<ActiveFriend> friends;

  /// Opens the voice channel a friend sits in.
  final ValueChanged<ConversationChannel> onOpenRoom;

  /// A fixed clock for tests. Without one the elapsed times follow the real
  /// clock, redrawn each minute.
  final DateTime? now;

  @override
  State<ActiveNowColumn> createState() => _ActiveNowColumnState();
}

class _ActiveNowColumnState extends State<ActiveNowColumn> {
  Timer? _minutes;

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _minutes = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _minutes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final now = widget.now ?? DateTime.now();
    return Container(
      key: const ValueKey('active-now'),
      width: ActiveNowColumn.width,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: surfaces.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Active now',
            style: FlucordTextRole.heading.style.copyWith(color: surfaces.text),
          ),
          const SizedBox(height: 16),
          if (widget.friends.isEmpty)
            Text(
              "It's quiet for now",
              style: FlucordTextRole.label.style.copyWith(
                color: surfaces.muted,
              ),
            ),
          for (final friend in widget.friends)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActiveFriendCard(
                friend: friend,
                now: now,
                onOpenRoom: widget.onOpenRoom,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveFriendCard extends StatelessWidget {
  const _ActiveFriendCard({
    required this.friend,
    required this.now,
    required this.onOpenRoom,
  });

  final ActiveFriend friend;
  final DateTime now;
  final ValueChanged<ConversationChannel> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final person = friend.person;
    final room = friend.room;
    final main = friend.doing.firstOrNull;
    final elapsed = ActivityElapsed.since(main?.timestamps, now);
    // A rich presence gets its own block, and the time moves there.
    final rich = main?.details == null ? null : main;
    final summary = ActivitySummary.of(friend.doing, inVoice: room != null);
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaces.raised,
        border: Border.all(color: surfaces.border),
        borderRadius: FlucordRadius.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MemberAvatar(
                member: person,
                size: 32,
                presenceBorderColor: surfaces.raised,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlucordTextRole.label.strong.copyWith(
                        color: surfaces.text,
                      ),
                    ),
                    if (summary != null)
                      Row(
                        children: [
                          Flexible(
                            child: ActivitySummaryLine(summary: summary),
                          ),
                          if (rich == null && elapsed != null)
                            Text(
                              ' · $elapsed',
                              style: FlucordTextRole.caption.style.copyWith(
                                color: surfaces.muted,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (rich != null) ...[
            const _CardDivider(),
            _Block(
              art: ArtTile(
                url: rich.assets?.largeImageUrl,
                monogram: monogramOf(rich.name),
                color: surfaces.inset,
              ),
              title: rich.details!,
              caption: [?rich.state, ?elapsed].join(' · '),
            ),
          ],
          if (room != null) ...[
            const _CardDivider(),
            _Block(
              art: ArtTile(
                url: room.space.iconUrl,
                monogram: room.space.monogram,
                color: Color(room.space.colorValue),
              ),
              title: room.channel.name,
              caption:
                  '${room.space.name} · ${peopleCount(room.people.length)}',
              trailing: OverlappingFaces(
                size: 20,
                ringColor: surfaces.raised,
                faces: [
                  for (final person in room.people.take(3))
                    MemberAvatar(member: person, size: 20, showPresence: false),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      button: room != null,
      child: Material(
        key: ValueKey('active-friend-${person.id}'),
        type: MaterialType.transparency,
        child: InkWell(
          onTap: room == null ? null : () => onOpenRoom(room.channel),
          borderRadius: FlucordRadius.medium,
          child: card,
        ),
      ),
    );
  }
}

/// The thin line between a card's top and one of its blocks.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(height: 1, thickness: 1, color: context.surfaces.border),
  );
}

/// A card's second block: a tile, a title, a caption, and maybe
/// something on the right.
class _Block extends StatelessWidget {
  const _Block({
    required this.art,
    required this.title,
    required this.caption,
    this.trailing,
  });

  final Widget art;
  final String title;
  final String caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Row(
      children: [
        art,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.strong.copyWith(
                  color: surfaces.text,
                ),
              ),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlucordTextRole.caption.style.copyWith(
                    color: surfaces.muted,
                  ),
                ),
            ],
          ),
        ),
        if (trailing case final trailing?) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }
}
