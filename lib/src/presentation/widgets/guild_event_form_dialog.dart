import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../profile_image_picker.dart';

/// Creates or edits one server event.
///
/// Hands back a draft for a new event, or an edit for an existing one, and
/// never both: which it is follows from whether the dialog was opened on an
/// event, the same way the AutoMod form works.
class GuildEventFormDialog extends StatefulWidget {
  const GuildEventFormDialog({
    required this.channels,
    this.event,
    this.imagePicker = const NativeProfileImagePicker(),
    super.key,
  });

  /// The voice and stage channels an event can be held in.
  final List<ConversationChannel> channels;

  final GuildScheduledEvent? event;

  /// Chooses the cover. Injected so a test can answer without a file dialog,
  /// and shared with the profile page rather than picked twice.
  final ProfileImagePicker imagePicker;

  @override
  State<GuildEventFormDialog> createState() => _GuildEventFormDialogState();
}

class _GuildEventFormDialogState extends State<GuildEventFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.event?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.event?.description ?? '',
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.event?.location ?? '',
  );

  late GuildScheduledEventEntityType _entityType =
      widget.event?.entityType ?? GuildScheduledEventEntityType.external;
  late String? _channelId = widget.event?.channelId;
  late DateTime _start =
      widget.event?.scheduledStartTime.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  late DateTime? _end = widget.event?.scheduledEndTime?.toLocal();

  /// The cover as chosen in this sitting. Absent means untouched, which is
  /// not the same as cleared — an edit has to tell Discord which it is.
  String? _coverImage;
  bool _coverCleared = false;

  bool get _isEditing => widget.event != null;
  bool get _isExternal => _entityType == GuildScheduledEventEntityType.external;

  @override
  void initState() {
    super.initState();
    for (final field in [_name, _description, _location]) {
      field.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final field in [_name, _description, _location]) {
      field
        ..removeListener(_onFieldChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('guild-event-form'),
    title: Text(_isEditing ? 'Edit event' : 'New event'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('event-name'),
              controller: _name,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Event name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('event-description'),
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'What is it about?',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GuildScheduledEventEntityType>(
              key: const ValueKey('event-where'),
              initialValue: _entityType,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Where',
              ),
              items: const [
                DropdownMenuItem(
                  value: GuildScheduledEventEntityType.external,
                  child: Text('Somewhere else'),
                ),
                DropdownMenuItem(
                  value: GuildScheduledEventEntityType.voice,
                  child: Text('A voice channel'),
                ),
                DropdownMenuItem(
                  value: GuildScheduledEventEntityType.stage,
                  child: Text('A stage channel'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _entityType = value ?? _entityType),
            ),
            if (_isExternal) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('event-location'),
                controller: _location,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Where exactly',
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('event-channel'),
                initialValue: _channelForKind.any((c) => c.id == _channelId)
                    ? _channelId
                    : null,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Channel',
                ),
                items: [
                  for (final channel in _channelForKind)
                    DropdownMenuItem(
                      value: channel.id,
                      child: Text(channel.name),
                    ),
                ],
                onChanged: (value) => setState(() => _channelId = value),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _coverLabel,
                    key: const ValueKey('event-cover-label'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  key: const ValueKey('event-cover-pick'),
                  onPressed: _pickCover,
                  child: const Text('Choose cover'),
                ),
                if (_coverImage != null ||
                    (_hasExistingCover && !_coverCleared))
                  IconButton(
                    key: const ValueKey('event-cover-clear'),
                    tooltip: 'Remove cover',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() {
                      _coverImage = null;
                      _coverCleared = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _WhenRow(
              label: 'Starts',
              fieldKey: const ValueKey('event-start'),
              value: _start,
              onPick: (picked) => setState(() => _start = picked),
            ),
            const SizedBox(height: 8),
            _WhenRow(
              label: 'Ends',
              fieldKey: const ValueKey('event-end'),
              value: _end,
              // Discord requires an end for an event it does not host, and
              // treats it as optional for one in a channel — so it can be
              // cleared there and not here.
              onPick: (picked) => setState(() => _end = picked),
              onClear: _isExternal ? null : () => setState(() => _end = null),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('event-save'),
        onPressed: _draft().isValid ? _save : null,
        child: Text(_isEditing ? 'Save' : 'Create'),
      ),
    ],
  );

  List<ConversationChannel> get _channelForKind => [
    for (final channel in widget.channels)
      if (_entityType == GuildScheduledEventEntityType.stage
          ? channel.isStage
          : channel.kind == ChannelKind.voice && !channel.isStage)
        channel,
  ];

  bool get _hasExistingCover => widget.event?.coverImageHash != null;

  String get _coverLabel {
    if (_coverImage != null) return 'Cover chosen';
    if (_coverCleared) return 'Cover will be removed';
    return _hasExistingCover ? 'Cover set' : 'No cover';
  }

  Future<void> _pickCover() async {
    final selection = await widget.imagePicker.pick();
    if (selection == null || !mounted) return;
    setState(() {
      _coverImage = selection.dataUri;
      _coverCleared = false;
    });
  }

  GuildScheduledEventDraft _draft() => GuildScheduledEventDraft(
    name: _name.text,
    description: _description.text,
    startTime: _start,
    endTime: _isExternal
        ? (_end ?? _start.add(const Duration(hours: 1)))
        : _end,
    entityType: _entityType,
    channelId: _isExternal ? null : _channelId,
    location: _location.text,
    coverImage: _coverImage,
  );

  void _save() {
    final draft = _draft();
    if (!_isEditing) {
      Navigator.of(context).pop(GuildEventFormResult.create(draft));
      return;
    }
    final event = widget.event!;
    final edit = GuildScheduledEventEdit();
    if (draft.name.trim() != event.name) edit.name = draft.name.trim();
    if (draft.description != (event.description ?? '')) {
      edit.description = draft.description;
    }
    if (draft.startTime.toUtc() != event.scheduledStartTime.toUtc()) {
      edit.startTime = draft.startTime;
    }
    if (draft.endTime?.toUtc() != event.scheduledEndTime?.toUtc()) {
      edit.endTime = draft.endTime;
    }
    if (draft.isExternal) {
      if (draft.location != (event.location ?? '')) {
        edit.location = draft.location;
      }
    } else if (draft.channelId != event.channelId) {
      edit.channelId = draft.channelId;
    }
    // Absent means untouched; cleared means take the cover off. Collapsing
    // the two would drop somebody's cover every time they renamed an event.
    if (_coverImage != null) {
      edit.coverImage = _coverImage;
    } else if (_coverCleared && _hasExistingCover) {
      edit.coverImage = null;
    }
    // An edit that changed nothing closes rather than being sent: the server
    // would take it and record a change nobody made.
    Navigator.of(
      context,
    ).pop(edit.isEmpty ? null : GuildEventFormResult.update(edit));
  }
}

/// What the form hands back.
final class GuildEventFormResult {
  const GuildEventFormResult.create(this.draft) : edit = null;
  const GuildEventFormResult.update(this.edit) : draft = null;

  final GuildScheduledEventDraft? draft;
  final GuildScheduledEventEdit? edit;
}

class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final Key fieldKey;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 56, child: Text(label)),
      Expanded(
        child: TextButton(
          key: fieldKey,
          onPressed: () => _pick(context),
          child: Text(value == null ? 'Not set' : _format(context, value!)),
        ),
      ),
      if (onClear != null && value != null)
        IconButton(
          key: ValueKey('${(fieldKey as ValueKey<String>).value}-clear'),
          tooltip: 'Clear',
          icon: const Icon(Icons.close, size: 16),
          onPressed: onClear,
        ),
    ],
  );

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? now),
    );
    if (time == null) return;
    onPick(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  static String _format(BuildContext context, DateTime when) {
    final material = MaterialLocalizations.of(context);
    final date = material.formatShortDate(when);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(when),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date, $time';
  }
}
