import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class GuildScheduledEventsDialog extends StatelessWidget {
  const GuildScheduledEventsDialog({
    required this.space,
    required this.workspace,
    required this.events,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    this.onSetInterest,
    this.onCreate,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final CommunitySpace space;
  final ChatWorkspace workspace;
  final List<GuildScheduledEvent> events;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRefresh;

  /// Says whether this account is interested in an event, or null on a
  /// transport that cannot say.
  final Future<bool> Function(GuildScheduledEvent, {required bool interested})?
  onSetInterest;

  /// Creates, edits and deletes an event. All null unless the account may
  /// manage events here, because Discord withholds the affordance rather than
  /// the request.
  final VoidCallback? onCreate;
  final void Function(GuildScheduledEvent)? onEdit;
  final void Function(GuildScheduledEvent)? onDelete;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('guild-events-dialog'),
    insetPadding: const EdgeInsets.all(24),
    backgroundColor: context.surfaces.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
      child: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            _EventsHeader(
              spaceName: space.name,
              onRefresh: onRefresh,
              onCreate: onCreate,
            ),
            Divider(height: 1, color: context.surfaces.border),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    if (isLoading && events.isEmpty) {
      return const _EventsState.loading();
    }
    if (error != null && events.isEmpty) {
      return _EventsState.error(onRetry: onRefresh);
    }
    if (events.isEmpty) return const _EventsState.empty();
    final active = events.where((event) => event.isActive).toList();
    final upcoming = events.where((event) => !event.isActive).toList();
    return ListView(
      key: const ValueKey('guild-events-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (active.isNotEmpty) ...[
          const _EventSectionLabel('Happening now'),
          for (final event in active) _row(event),
        ],
        if (upcoming.isNotEmpty) ...[
          if (active.isNotEmpty) const SizedBox(height: 18),
          const _EventSectionLabel('Upcoming'),
          for (final event in upcoming) _row(event),
        ],
        if (error != null) _InlineEventError(onRetry: onRefresh),
      ],
    );
  }

  Widget _row(GuildScheduledEvent event) {
    final channel = event.channelId == null
        ? null
        : workspace.channelOrNull(event.channelId!);
    return _ScheduledEventRow(
      event: event,
      channel: channel,
      canOpen: channel != null,
      onSetInterest: onSetInterest,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _EventsHeader extends StatelessWidget {
  const _EventsHeader({
    required this.spaceName,
    required this.onRefresh,
    this.onCreate,
  });

  final String spaceName;
  final VoidCallback onRefresh;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Row(
      children: [
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Events',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                spaceName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('refresh-guild-events'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 19),
          tooltip: 'Refresh events',
        ),
        if (onCreate != null)
          IconButton(
            key: const ValueKey('create-guild-event'),
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 19),
            tooltip: 'Create event',
          ),
        IconButton(
          key: const ValueKey('close-guild-events'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 19),
          tooltip: 'Close events',
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
}

class _ScheduledEventRow extends StatelessWidget {
  const _ScheduledEventRow({
    required this.event,
    required this.channel,
    required this.canOpen,
    this.onSetInterest,
    this.onEdit,
    this.onDelete,
  });

  final GuildScheduledEvent event;
  final ConversationChannel? channel;
  final bool canOpen;

  /// Says whether this account is interested, or null on a transport that
  /// cannot say — in which case the control is not offered at all.
  final Future<bool> Function(GuildScheduledEvent, {required bool interested})?
  onSetInterest;
  final void Function(GuildScheduledEvent)? onEdit;
  final void Function(GuildScheduledEvent)? onDelete;

  @override
  Widget build(BuildContext context) {
    final localStart = event.scheduledStartTime.toLocal();
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(localStart),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final destination =
        event.location ??
        (channel == null
            ? _entityLabel(event.entityType)
            : '#${channel!.name}');
    return Semantics(
      button: canOpen,
      label: '${event.name}, $time, $destination',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('guild-event-${event.id}'),
          onTap: !canOpen ? null : () => Navigator.of(context).pop(channel!.id),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EventDate(start: localStart, active: event.isActive),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.isActive) const _LiveLabel(),
                      Text(
                        event.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$time  |  $destination',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.surfaces.muted,
                        ),
                      ),
                      if (event.description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Text(
                            '${event.interestedCount} interested',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.surfaces.muted,
                            ),
                          ),
                          if (onSetInterest != null) ...[
                            const SizedBox(width: 10),
                            _InterestButton(
                              event: event,
                              onSetInterest: onSetInterest!,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    key: ValueKey('guild-event-edit-${event.id}'),
                    tooltip: 'Edit event',
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: () => onEdit!(event),
                  ),
                if (onDelete != null)
                  IconButton(
                    key: ValueKey('guild-event-delete-${event.id}'),
                    tooltip: 'Delete event',
                    icon: const Icon(Icons.delete_outline, size: 16),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: () => onDelete!(event),
                  ),
                if (canOpen)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Icon(Icons.chevron_right, size: 19),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _entityLabel(GuildScheduledEventEntityType type) =>
      switch (type) {
        GuildScheduledEventEntityType.stage => 'Stage channel',
        GuildScheduledEventEntityType.voice => 'Voice channel',
        GuildScheduledEventEntityType.external => 'External event',
        GuildScheduledEventEntityType.unknown => 'Server event',
      };
}

class _EventDate extends StatelessWidget {
  const _EventDate({required this.start, required this.active});

  final DateTime start;
  final bool active;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 52,
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      border: Border.all(color: context.surfaces.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          active ? 'NOW' : _months[start.month - 1],
          style: TextStyle(
            color: active ? FlucordColors.success : FlucordColors.mention,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${start.day}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _LiveLabel extends StatelessWidget {
  const _LiveLabel();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 4),
    child: Text(
      'LIVE NOW',
      style: TextStyle(
        color: FlucordColors.success,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EventSectionLabel extends StatelessWidget {
  const _EventSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.surfaces.muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EventsState extends StatelessWidget {
  const _EventsState.loading() : icon = null, title = null, onRetry = null;

  const _EventsState.empty()
    : icon = Icons.event_available_outlined,
      title = 'No upcoming events',
      onRetry = null;

  const _EventsState.error({required this.onRetry})
    : icon = Icons.event_busy_outlined,
      title = 'Events unavailable';

  final IconData? icon;
  final String? title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: icon == null
        ? const CircularProgressIndicator(strokeWidth: 2)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: context.surfaces.muted),
              const SizedBox(height: 10),
              Text(title!, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
  );
}

class _InlineEventError extends StatelessWidget {
  const _InlineEventError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Refresh failed - retry'),
    ),
  );
}

/// The interested toggle on one event.
///
/// Optimistic in appearance only: the label flips while the request is in
/// flight and flips back if Discord refused, because the count it sits beside
/// moves on the dispatch rather than on this tap.
class _InterestButton extends StatefulWidget {
  const _InterestButton({required this.event, required this.onSetInterest});

  final GuildScheduledEvent event;
  final Future<bool> Function(GuildScheduledEvent, {required bool interested})
  onSetInterest;

  @override
  State<_InterestButton> createState() => _InterestButtonState();
}

class _InterestButtonState extends State<_InterestButton> {
  bool _interested = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey('guild-event-interest-${widget.event.id}'),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11),
    ),
    onPressed: _busy ? null : _toggle,
    child: Text(_interested ? 'Not interested' : 'Interested'),
  );

  Future<void> _toggle() async {
    final next = !_interested;
    setState(() {
      _busy = true;
      _interested = next;
    });
    final accepted = await widget.onSetInterest(widget.event, interested: next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // An event that has already ended is refused; the label goes back rather
      // than claiming an RSVP that was never recorded.
      if (!accepted) _interested = !next;
    });
  }
}
